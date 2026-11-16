$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DeployPath = Join-Path $ScriptsDir 'prod\deploy-prod.ps1'
$StatusPath = Join-Path $ScriptsDir 'prod\prod-status.ps1'
Import-Module (Join-Path $ScriptsDir 'lib\script-discovery.psm1') -Force
. (Join-Path $ScriptsDir 'prod\prod-common.ps1')

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Git([string]$Root, [string[]]$Arguments) {
    $log = & git -C $Root -c user.name=Test -c user.email=test@example.invalid @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Root}: $log" }
}

function New-TextFile([string]$Path, [string]$Content) {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, $Content)
}

function Invoke-Script([string]$Script, [string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $Script @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
}

function Invoke-Deploy([string[]]$Arguments) {
    return Invoke-Script $DeployPath (@('-Target', $repo) + $Arguments)
}

# A release commit: the source says its version, and the check refuses a
# source that says 'broken'.
function Save-Release([string]$Text, [string]$Tag, [switch]$NoPush) {
    New-TextFile (Join-Path $repo 'src\app.txt') $Text
    Invoke-Git $repo @('add', '-A')
    Invoke-Git $repo @('commit', '--quiet', '-m', "release $Text")
    if ($Tag) { Invoke-Git $repo @('tag', '-a', $Tag, '-m', $Tag) }
    if (-not $NoPush) { Invoke-Git $repo @('push', '--quiet', '--follow-tags', 'origin', 'main') }
}

# The Header the menu reads: Update, Rollback and Status, the rollback marked.
$header = Read-ScriptHeader -Path $DeployPath
Assert-Equal 'Described' $header.Status 'deploy-prod has a valid Header'
Assert-Equal '|-Rollback|-Status' (@($header.Actions | ForEach-Object Arguments) -join '|') 'deploy-prod offers Update, Rollback and Status'
Assert-Equal $true $header.Actions[1].Danger 'the rollback is a danger action'
Assert-Equal $null $header.VariantParameter 'deploy-prod has no Variant axis'
Assert-Equal 'Described' (Read-ScriptHeader -Path $StatusPath).Status 'prod-status has a valid Header'
foreach ($helper in 'prod-common.ps1', 'prod-start.ps1') {
    Assert-True ((Read-ScriptHeader -Path (Join-Path $ScriptsDir "prod\$helper")).Status -ne 'Described') "$helper stays hidden from the menu"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "prod-$([guid]::NewGuid())"
$projects = Join-Path $temp 'projects'
$repo = Join-Path $projects 'app'
$origin = Join-Path $temp 'origin.git'
$prod = Join-Path $temp 'prod'
$buildTree = Join-Path $temp 'worktrees\app\prod-build'
$running = $null
try {
    $null = New-Item -ItemType Directory -Path $repo
    Invoke-Git $temp @('init', '--quiet', '--bare', $origin)
    Invoke-Git $repo @('init', '--quiet', '-b', 'main')
    Invoke-Git $repo @('remote', 'add', 'origin', $origin)

    # The build copies the source into out\ with the version it was given; the
    # check reads it back. Both run in the snapshot, not in this checkout.
    New-TextFile (Join-Path $repo 'scripts\prod.settings.psd1') @'
@{
    Build  = 'New-Item -ItemType Directory -Force out | Out-Null; Copy-Item src\app.txt out\; Set-Content out\version.txt $env:PROD_VERSION; Copy-Item src\run.ps1 out\'
    Check  = 'if ((Get-Content "$env:PROD_OUTPUT\app.txt" -Raw) -match "broken") { exit 3 }'
    Output = 'out'
    Start  = 'run.ps1'
    StartArguments = @('--from-stamp')
    Carry  = @('data')
}
'@
    # The program: it records how it was started, and waits while a wait file exists.
    New-TextFile (Join-Path $repo 'src\run.ps1') @'
Set-Content (Join-Path $PSScriptRoot 'started.txt') ($args -join ' ')
while (Test-Path (Join-Path $PSScriptRoot 'wait.txt')) { Start-Sleep -Milliseconds 100 }
'@
    New-TextFile (Join-Path $repo '.gitignore') "prod/`n"
    Save-Release 'one' 'v0.1.0'

    # The settings: defaults filled, the contract enforced.
    $settings = Read-ProdSettings -Primary $repo
    Assert-Equal 'start' $settings.Swap 'Swap defaults to the generic start wrapper'
    Assert-Equal 'main' $settings.Branch 'the lag is read against main by default'
    Assert-Equal $buildTree (Get-ProdBuildTree -Primary $repo) 'the build tree is <worktrees>\<repo>\prod-build beside the projects folder'

    # First deploy: the latest tag on origin lands in current\, with its stamp
    # and the start wrapper.
    $first = Invoke-Deploy @('-Root', $prod)
    Assert-Equal 0 $first.Code "the first deploy succeeds: $($first.Text)"
    Assert-Equal 'one' (Get-Content (Join-Path $prod 'current\app.txt') -Raw) 'the first deploy writes current\'
    Assert-Equal 'v0.1.0' (Read-ProdStamp -Folder (Join-Path $prod 'current')).version 'the stamp records the version'
    Assert-Equal 'v0.1.0' (Get-Content (Join-Path $prod 'current\version.txt') -Raw).Trim() 'the build gets the version in PROD_VERSION'
    Assert-True (Test-Path -LiteralPath (Join-Path $prod 'start.ps1')) 'Swap start writes the start wrapper'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $prod 'current\.git'))) 'the prod copy carries no link to the repository'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo 'out'))) 'nothing is built in the working checkout'

    $again = Invoke-Deploy @('-Root', $prod)
    Assert-Equal 0 $again.Code 'a second deploy of the same version succeeds'
    Assert-True ($again.Text -match 'Skipped') 'a version already running is skipped'

    # A tag recorded but not pushed is not what ships, and a local edit never
    # reaches the snapshot.
    Save-Release 'two' 'v0.2.0' -NoPush
    New-TextFile (Join-Path $repo 'src\app.txt') 'uncommitted'
    $unpushed = Invoke-Deploy @('-Root', $prod, '-Ref', 'v0.2.0')
    Assert-True ($unpushed.Code -ne 0) 'a commit origin does not hold is refused'
    Assert-True ($unpushed.Text -match 'origin') 'the refusal names origin'
    Invoke-Git $repo @('checkout', '--quiet', '--', 'src/app.txt')
    Invoke-Git $repo @('push', '--quiet', '--follow-tags', 'origin', 'main')

    # A newer version waits in next\; current\ is never touched.
    $second = Invoke-Deploy @('-Root', $prod)
    Assert-Equal 0 $second.Code "the second deploy succeeds: $($second.Text)"
    Assert-Equal 'two' (Get-Content (Join-Path $prod 'next\app.txt') -Raw) 'the new version waits in next\'
    Assert-Equal 'one' (Get-Content (Join-Path $prod 'current\app.txt') -Raw) 'current\ is left as it runs'

    # A failing check leaves the prod copy as it was.
    Save-Release 'broken' 'v0.3.0'
    $failed = Invoke-Deploy @('-Root', $prod)
    Assert-True ($failed.Code -ne 0) 'a failing check fails the deploy'
    Assert-Equal 'two' (Get-Content (Join-Path $prod 'next\app.txt') -Raw) 'a failed deploy leaves next\ as it was'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $prod 'next.staging'))) 'a failed deploy leaves no staging folder'

    # The status: what runs, what waits, how far behind origin.
    $status = Invoke-Deploy @('-Root', $prod, '-Status')
    Assert-Equal 0 $status.Code 'the status succeeds'
    Assert-True ($status.Text -match 'v0\.1\.0' -and $status.Text -match 'v0\.2\.0' -and $status.Text -match 'v0\.3\.0') 'the status names running, staged and origin versions'
    Assert-True ($status.Text -match '2 commit\(s\) behind origin/main') 'the status counts the commits behind origin'

    # The start wrapper does not swap while a program runs from current\.
    New-TextFile (Join-Path $prod 'current\wait.txt') 'x'
    New-TextFile (Join-Path $prod 'current\data\keep.txt') 'machine data'
    $startedFile = Join-Path $prod 'current\started.txt'
    function Wait-Started {
        $deadline = (Get-Date).AddSeconds(30)
        while (-not (Test-Path -LiteralPath $startedFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Assert-True (Test-Path -LiteralPath $startedFile) 'the program started'
        Remove-Item -LiteralPath $startedFile
    }
    $running = Start-Process pwsh -ArgumentList '-NoProfile', '-File', "`"$(Join-Path $prod 'current\run.ps1')`"" -PassThru -WindowStyle Hidden
    Wait-Started
    # A second start while the first runs: it starts current\ as it is.
    $busy = Start-Process pwsh -ArgumentList '-NoProfile', '-File', "`"$(Join-Path $prod 'start.ps1')`"" -PassThru -WindowStyle Hidden
    Wait-Started
    Assert-Equal 'one' (Get-Content (Join-Path $prod 'current\app.txt') -Raw) 'no swap while a program runs from current\'
    Assert-True (Test-Path -LiteralPath (Join-Path $prod 'next\app.txt')) 'next\ keeps waiting while current\ runs'
    Remove-Item -LiteralPath (Join-Path $prod 'current\wait.txt')
    $running.WaitForExit(20000) | Out-Null
    $busy.WaitForExit(20000) | Out-Null
    $running = $null
    Remove-Item -LiteralPath $startedFile -ErrorAction SilentlyContinue

    # Once nothing runs, the next start swaps next\ in and starts it.
    $start = Invoke-Script (Join-Path $prod 'start.ps1') @('--extra')
    Assert-Equal 0 $start.Code "the start succeeds: $($start.Text)"
    Assert-Equal 'two' (Get-Content (Join-Path $prod 'current\app.txt') -Raw) 'the start swaps next\ into current\'
    Assert-Equal 'one' (Get-Content (Join-Path $prod 'previous\app.txt') -Raw) 'the replaced build is kept in previous\'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $prod 'next'))) 'next\ is gone once swapped in'
    Assert-Equal '--from-stamp --extra' (Get-Content (Join-Path $prod 'current\started.txt') -Raw).Trim() 'the start passes the stamp''s arguments, then its own'
    Assert-Equal 'machine data' (Get-Content (Join-Path $prod 'current\data\keep.txt') -Raw) 'the Carry folders follow the build that runs'

    # Rollback stages previous\ for the next start.
    $rollback = Invoke-Deploy @('-Root', $prod, '-Rollback')
    Assert-Equal 0 $rollback.Code "the rollback succeeds: $($rollback.Text)"
    Assert-Equal 'one' (Get-Content (Join-Path $prod 'next\app.txt') -Raw) 'the rollback stages previous\ as next\'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $prod 'previous'))) 'previous\ moves to next\'
    $none = Invoke-Deploy @('-Root', $prod, '-Rollback')
    Assert-True ($none.Code -ne 0) 'a rollback with no previous build is refused'

    # A current\ without a stamp is a build that may run: never overwritten.
    $legacy = Join-Path $temp 'legacy'
    New-TextFile (Join-Path $legacy 'current\old.exe') 'running'
    $adopt = Invoke-Deploy @('-Root', $legacy, '-Ref', 'v0.2.0')
    Assert-Equal 0 $adopt.Code "a deploy beside an unstamped current\ succeeds: $($adopt.Text)"
    Assert-Equal 'running' (Get-Content (Join-Path $legacy 'current\old.exe') -Raw) 'an unstamped current\ is left alone'
    Assert-Equal 'two' (Get-Content (Join-Path $legacy 'next\app.txt') -Raw) 'the build waits in next\ beside it'

    # The status of every project walks the folder and skips repositories
    # without prod settings.
    $null = New-Item -ItemType Directory -Path (Join-Path $projects 'library')
    Invoke-Git (Join-Path $projects 'library') @('init', '--quiet')
    New-TextFile (Join-Path $repo 'scripts\prod.settings.psd1') ((Get-Content (Join-Path $repo 'scripts\prod.settings.psd1') -Raw).Replace("Carry  = @('data')", "Carry  = @('data')`n    Root   = '$($prod.Replace("'", "''"))'"))
    $all = Invoke-Script $StatusPath @('-Path', $projects)
    Assert-Equal 0 $all.Code "the status of every project succeeds: $($all.Text)"
    Assert-True ($all.Text -match 'app' -and $all.Text -match 'running\s+v0\.2\.0') 'the status names the running version of each project'
    Assert-True ($all.Text -match 'No prod\s*:\s*library') 'a repository without prod settings is listed apart'
} finally {
    if ($running -and -not $running.HasExited) { Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host 'deploy-prod.tests.ps1: PASS' -ForegroundColor Green
