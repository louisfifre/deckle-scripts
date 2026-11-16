<#
.SYNOPSIS
    Deploy to prod
.DESCRIPTION
    Builds a version origin holds in a snapshot of its own, checks it, and
    stages it in the repository's prod copy, the build the maintainer runs
    every day. What runs is never stopped: the staged build takes its place at
    the next start. Rollback stages the previous build the same way; Status
    says what runs, what waits and how far it is behind origin.
.NOTES
    order: 100
    action: Update prod |
    action: Roll back prod | -Rollback | danger | Stages the previous build; the app runs it from its next start.
    action: Prod status | -Status
#>

# What the deploy does, in order (scripts/prod/README.md says why):
#   1. resolve the ref on origin: the highest version tag by default;
#   2. check that commit out in <worktrees>\<repo>\prod-build, a detached
#      worktree reserved to this script, outside every checkout someone edits;
#   3. run the Build command, then the Check command, in that snapshot;
#   4. copy the Output folder into <Root>\next.staging with its stamp, then
#      rename it to next\ (current\ on the first deploy): a start never sees
#      half a build;
#   5. with Swap 'start', refresh <Root>\start.ps1, the wrapper that swaps
#      next\ in at the next start.
# A failure at any step leaves the prod copy as it was.

[CmdletBinding()]
param(
    # What to deploy: a version tag, a branch or a commit origin holds. By
    # default the highest version tag on origin.
    [string]$Ref,
    # Stage previous\ as next\ instead of building: the next start rolls back.
    [switch]$Rollback,
    # Report the prod copy and change nothing.
    [switch]$Status,
    # Stage even when the commit is already the one staged or running.
    [switch]$Force,
    # Root of the repository to deploy; without it, the repository that holds
    # this script.
    [string]$Target,
    # The prod root, instead of the one the settings name: for a test.
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$LibDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
. (Join-Path $LibDir 'action-summary.ps1')
. (Join-Path $PSScriptRoot 'prod-common.ps1')

$Workflow = if ($Status) { 'Prod status' } elseif ($Rollback) { 'Roll back prod' } else { 'Update prod' }
$Primary = $null; $Layout = $null; $Resolved = $null; $BuildTree = $null; $Lock = $null

trap {
    # Only a run that holds the lock owns next.staging; another run's is left alone.
    if ($Lock -and (Test-Path -LiteralPath $Layout.Staging)) {
        Remove-Item -LiteralPath $Layout.Staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($Lock) { $Lock.Dispose() }
    $sentence = if ($Status) { 'The prod status could not be read.' } else { 'The prod copy was not changed; what runs is untouched.' }
    Write-ActionSummary -Workflow $Workflow -Result Failed -Sentence $sentence `
        -Details ([ordered]@{
            Root      = $Layout.Root
            Ref       = $Resolved.Ref
            Commit    = $Resolved.Commit
            BuildTree = $BuildTree
            Error     = $_.Exception.Message
        })
    throw
}

$from = if ($Target) { (Resolve-Path -LiteralPath $Target).Path } else { $PSScriptRoot }
$Primary = Get-ProdPrimaryCheckout -From $from
$Settings = Read-ProdSettings -Primary $Primary
$Layout = Get-ProdLayout -Root (Resolve-ProdRoot -Primary $Primary -Settings $Settings -Root $Root)
$output = New-WorkflowOutput -Category 'prod'

if ($Status) {
    $state = Get-ProdState -Primary $Primary -Root $Layout.Root
    $sentence = if ($state.StagedStamp) { "$($state.Staged) waits for the next start." } else { 'Nothing waits for the next start.' }
    Write-ActionSummary -Workflow $Workflow -Result Success -Sentence $sentence `
        -Details ([ordered]@{
            Root     = $state.Root
            Running  = $state.Running
            Staged   = $state.Staged
            Previous = $state.Previous
            Origin   = $state.Latest
            Lag      = Format-ProdBehind $state
            Warning  = $state.OriginError
        })
    return
}

$null = New-Item -ItemType Directory -Force -Path $Layout.Root
# One deploy at a time per prod copy: the handle is released when this process
# ends, however it ends, so a crash never leaves the lock behind.
try {
    $Lock = [IO.File]::Open($Layout.Lock, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch [IO.IOException] {
    throw "Another deploy is writing $($Layout.Root); run this again once it ends."
}

if ($Rollback) {
    if (-not (Test-ProdSlot -Folder $Layout.Previous)) { throw "No previous build under $($Layout.Previous) to roll back to." }
    $replaced = Format-ProdSlot -Folder $Layout.Next
    if (Test-Path -LiteralPath $Layout.Next) { Remove-Item -LiteralPath $Layout.Next -Recurse -Force }
    Rename-Item -LiteralPath $Layout.Previous -NewName 'next'
    $Lock.Dispose()
    Write-ActionSummary -Workflow $Workflow -Result Success `
        -Sentence 'The previous build is staged; the app runs it from its next start.' `
        -Details ([ordered]@{
            Root     = $Layout.Root
            Staged   = Format-ProdSlot -Folder $Layout.Next
            Running  = Format-ProdSlot -Folder $Layout.Current
            Replaced = $(if ($replaced -ne 'none') { $replaced })
        })
    return
}

Write-WorkflowStep -Output $output -Message "Resolve $(if ($Ref) { $Ref } else { 'the latest version' }) on origin"
$Resolved = Resolve-ProdCommit -Primary $Primary -Ref $Ref
Write-WorkflowMessage -Output $output -Message "$($Resolved.Ref) = $($Resolved.Commit) ($($Resolved.Version))"

if (-not $Force) {
    $staged = Read-ProdStamp -Folder $Layout.Next
    $running = Read-ProdStamp -Folder $Layout.Current
    $place = if ($staged -and $staged.commit -eq $Resolved.Commit) { 'staged' }
             elseif (-not $staged -and -not (Test-ProdSlot -Folder $Layout.Next) -and $running -and $running.commit -eq $Resolved.Commit) { 'running' }
    if ($place) {
        $Lock.Dispose()
        Write-ActionSummary -Workflow $Workflow -Result Skipped `
            -Sentence "$($Resolved.Version) is already $place in the prod copy." `
            -Details ([ordered]@{ Root = $Layout.Root; Ref = $Resolved.Ref; Commit = $Resolved.Commit }) `
            -Next @('Pass -Force to build and stage it again.')
        return
    }
}

$BuildTree = Get-ProdBuildTree -Primary $Primary
Write-WorkflowStep -Output $output -Message "Check out $($Resolved.Commit.Substring(0, 7)) in $BuildTree"
& git -C $Primary worktree prune 2>$null
if (Test-Path -LiteralPath (Join-Path $BuildTree '.git')) {
    # Nobody edits this tree; --force discards whatever an interrupted run left.
    $log = @(& git -C $BuildTree checkout --quiet --force --detach $Resolved.Commit 2>&1 | ForEach-Object { [string]$_ })
} else {
    if (Test-Path -LiteralPath $BuildTree) { throw "$BuildTree exists and is no worktree: move it away, it is reserved to the prod build." }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BuildTree)
    $log = @(& git -C $Primary worktree add --quiet --detach $BuildTree $Resolved.Commit 2>&1 | ForEach-Object { [string]$_ })
}
if ($LASTEXITCODE -ne 0) { throw "git could not check out $($Resolved.Commit) in ${BuildTree}: $($log -join ' ')" }
if ($Settings.Clean) {
    $log = @(& git -C $BuildTree clean -ffdxq 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "git could not clean ${BuildTree}: $($log -join ' ')" }
}

$outputPath = [IO.Path]::GetFullPath((Join-Path $BuildTree $Settings.Output))
$environment = [ordered]@{
    PROD_SNAPSHOT = $BuildTree
    PROD_OUTPUT   = $outputPath
    PROD_COMMIT   = $Resolved.Commit
    PROD_VERSION  = $Resolved.Version
    PROD_PRIMARY  = $Primary
}

if ($Settings.Build) {
    Write-WorkflowStep -Output $output -Message 'Build'
    Write-WorkflowMessage -Output $output -Message $Settings.Build -Role Muted
    Invoke-ProdCommand -Command $Settings.Build -WorkingDirectory $BuildTree -Environment $environment -Name 'Build'
}
if (-not (Test-ProdSlot -Folder $outputPath)) { throw "The build left nothing in its Output folder $outputPath." }

Write-WorkflowStep -Output $output -Message 'Check'
Write-WorkflowMessage -Output $output -Message $Settings.Check -Role Muted
Invoke-ProdCommand -Command $Settings.Check -WorkingDirectory $BuildTree -Environment $environment -Name 'Check'

Write-WorkflowStep -Output $output -Message "Stage into $($Layout.Root)"
if (Test-Path -LiteralPath $Layout.Staging) { Remove-Item -LiteralPath $Layout.Staging -Recurse -Force }
# The worktree's .git file links it to the repository; a prod copy is no checkout.
& robocopy $outputPath $Layout.Staging /MIR /XD .git /XF .git /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed copying $outputPath (exit code $LASTEXITCODE)." }
Write-ProdStamp -Folder $Layout.Staging -Stamp ([ordered]@{
    version        = $Resolved.Version
    commit         = $Resolved.Commit
    ref            = $Resolved.Ref
    deployedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    start          = $Settings.Start
    startArguments = $Settings.StartArguments
    carry          = $Settings.Carry
})

# A current\ holding anything is a build someone may run, stamped or not: it
# is never overwritten, the new build waits in next\ instead.
$firstDeploy = -not (Test-ProdSlot -Folder $Layout.Current)
if ($firstDeploy) {
    if (Test-Path -LiteralPath $Layout.Current) { Remove-Item -LiteralPath $Layout.Current -Recurse -Force }
    Rename-Item -LiteralPath $Layout.Staging -NewName 'current'
} else {
    # A build staged earlier and never started gives way to this one.
    if (Test-Path -LiteralPath $Layout.Next) { Remove-Item -LiteralPath $Layout.Next -Recurse -Force }
    Rename-Item -LiteralPath $Layout.Staging -NewName 'next'
}

if ($Settings.Swap -eq 'start') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'prod-start.ps1') -Destination $Layout.Start -Force
}
$Lock.Dispose()

$startLine = if ($Settings.Swap -eq 'start') { "pwsh -NoProfile -File `"$($Layout.Start)`"" } else { 'the app swaps next\ in itself' }
$sentence = if ($firstDeploy) {
    "$($Resolved.Version) is installed in current\; start it once to run it."
} else {
    "$($Resolved.Version) is staged; the app runs it from its next start."
}
Write-ActionSummary -Workflow $Workflow -Result Success -Sentence $sentence `
    -Details ([ordered]@{
        Root    = $Layout.Root
        Version = $Resolved.Version
        Commit  = $Resolved.Commit
        Running = Format-ProdSlot -Folder $Layout.Current
        Staged  = Format-ProdSlot -Folder $Layout.Next
        Start   = $startLine
    })
