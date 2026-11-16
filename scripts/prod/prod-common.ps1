# Steps shared by the scripts of the prod pack, dot-sourced by each of them.
#
# This file has no Header on purpose: the menu lists scripts a person can run,
# and this one only serves the others, so it stays hidden beside them.
#
# The prod copy of a repository, under its Root (prod\ in the primary checkout
# by default, ignored by git):
#   current\       the build that runs
#   next\          a complete build waiting for the next start
#   previous\      the build current\ replaced, kept for a rollback
#   next.staging\  a build being written; nothing ever starts from it
#   start.ps1      the generic start wrapper, when the project uses it
# Each slot carries a stamp, .prod.json, that says which commit and version it
# holds and how it starts. The stamp travels with its folder at every rename,
# so whoever swaps the slots (start.ps1 or the app itself) moves it along.

$script:ProdStampName = '.prod.json'
$script:ProdSettingsKeys = @('Build', 'Check', 'Output', 'Start', 'StartArguments', 'Swap', 'Root', 'Branch', 'Clean', 'Carry')

# The primary checkout, whatever worktree the path sits in: the prod root and
# the build worktree are both derived from it, so a deploy run from a feature
# worktree still writes the one prod copy.
function Get-ProdPrimaryCheckout {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$From)

    $lines = @(& git -C $From rev-parse --path-format=absolute --git-common-dir 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) {
        throw "'$From' is not inside a git repository. Pass -Target with the root of one."
    }
    return [IO.Path]::GetFullPath((Split-Path -Parent $lines[0].Trim()))
}

# <parent of the projects folder>\worktrees\<repo>, the convention every
# repository of the maintainer follows: C:\Code\projects\deckle gives
# C:\Code\worktrees\deckle.
function Get-ProdBuildTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Primary)

    $container = Join-Path (Split-Path -Parent (Split-Path -Parent $Primary)) 'worktrees'
    return Join-Path (Join-Path $container (Split-Path -Leaf $Primary)) 'prod-build'
}

function Get-ProdSettingsPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Primary)

    # Beside the pack, not inside it: the pack folder is owned by the install,
    # and an update must never meet a file of the project there.
    return Join-Path $Primary 'scripts\prod.settings.psd1'
}

# The project's settings, with the defaults filled in. A .psd1 is read by
# Import-PowerShellDataFile, which evaluates no code: reading the settings can
# never run anything, only the commands they name run, and only when asked.
function Read-ProdSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Primary)

    $path = Get-ProdSettingsPath -Primary $Primary
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "No prod settings at '$path'. Write one from scripts/prod/README.md to give this repository a prod copy."
    }
    try {
        $data = Import-PowerShellDataFile -LiteralPath $path
    } catch {
        throw "The prod settings '$path' are not a valid PowerShell data file: $($_.Exception.Message)"
    }

    $unknown = @($data.Keys | Where-Object { $_ -notin $script:ProdSettingsKeys })
    if ($unknown.Count -gt 0) {
        throw "The prod settings '$path' name unknown key(s): $($unknown -join ', '). Known keys: $($script:ProdSettingsKeys -join ', ')."
    }

    $settings = [ordered]@{
        Path           = $path
        Build          = [string]$data['Build']
        Check          = [string]$data['Check']
        Output         = [string]$data['Output']
        Start          = [string]$data['Start']
        StartArguments = [string[]]@($data['StartArguments'] | Where-Object { $null -ne $_ })
        Swap           = if ($data['Swap']) { [string]$data['Swap'] } else { 'start' }
        Root           = if ($data['Root']) { [string]$data['Root'] } else { 'prod' }
        Branch         = if ($data['Branch']) { [string]$data['Branch'] } else { 'main' }
        Clean          = [bool]$data['Clean']
        Carry          = [string[]]@($data['Carry'] | Where-Object { $_ })
    }

    # The contract every prod copy keeps: a check passes before anything is
    # put in place. A project with nothing to check says so in its command.
    if (-not $settings.Check) { throw "The prod settings '$path' name no Check: a build is put in place only once a check passed." }
    if (-not $settings.Output) { throw "The prod settings '$path' name no Output: the folder of the snapshot that becomes the prod copy ('.' for the whole snapshot)." }
    if ($settings.Swap -notin @('start', 'app')) { throw "The prod settings '$path' give Swap '$($settings.Swap)': it is 'start' (the generic start.ps1 swaps the slots) or 'app' (the app swaps them itself)." }
    if ($settings.Swap -eq 'start' -and -not $settings.Start) { throw "The prod settings '$path' name no Start: with Swap 'start', start.ps1 needs the program to start, relative to the slot." }
    foreach ($name in $settings.Carry) {
        if ($name -match '[\\/]|^\.\.?$') { throw "The prod settings '$path' carry '$name': Carry names folders directly in the slot." }
    }
    return [pscustomobject]$settings
}

function Resolve-ProdRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Primary,
        [Parameter(Mandatory)]$Settings,
        [string]$Root
    )

    $value = if ($Root) { $Root } else { $Settings.Root }
    if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path $Primary $value }
    return [IO.Path]::GetFullPath($value)
}

function Get-ProdLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    return [pscustomobject]@{
        Root     = $Root
        Current  = Join-Path $Root 'current'
        Next     = Join-Path $Root 'next'
        Previous = Join-Path $Root 'previous'
        Staging  = Join-Path $Root 'next.staging'
        Start    = Join-Path $Root 'start.ps1'
        Lock     = Join-Path $Root 'deploy.lock'
    }
}

# True when the folder exists and holds anything: an empty current\ is a first
# deploy, a current\ with files in it is a build someone may be running.
function Test-ProdSlot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $false }
    return $null -ne (Get-ChildItem -LiteralPath $Folder -Force | Select-Object -First 1)
}

function Read-ProdStamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)

    $path = Join-Path $Folder $script:ProdStampName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-ProdStamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)]$Stamp
    )

    $json = ($Stamp | ConvertTo-Json -Depth 4).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText((Join-Path $Folder $script:ProdStampName), $json, [Text.UTF8Encoding]::new($false))
}

# One line for a slot: its version and short commit, or why there is none.
function Format-ProdSlot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)

    $stamp = Read-ProdStamp -Folder $Folder
    if ($stamp) { return "$($stamp.version) ($(([string]$stamp.commit).Substring(0, 7)))" }
    if (Test-ProdSlot -Folder $Folder) { return 'a build with no stamp' }
    return 'none'
}

# The refs origin holds, peeled: a tag maps to the commit it names, not to the
# tag object. ls-remote asks origin itself, so a tag recorded here and never
# pushed is not among them.
function Get-ProdOriginRefs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Primary)

    $lines = @(& git -C $Primary ls-remote origin 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "git could not reach origin from '$Primary': $($lines -join ' ')" }
    $refs = [ordered]@{}
    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9a-f]{40})\s+(\S+)$') { continue }
        $sha = $Matches[1]; $name = $Matches[2]
        if ($name.EndsWith('^{}')) { $refs[$name.Substring(0, $name.Length - 3)] = $sha } elseif (-not $refs.Contains($name)) { $refs[$name] = $sha }
    }
    return $refs
}

function Get-ProdLatestOriginTag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$OriginRefs)

    $tags = foreach ($name in $OriginRefs.Keys) {
        if ($name -match '^refs/tags/(v(\d+)\.(\d+)\.(\d+))$') {
            [pscustomobject]@{ Tag = $Matches[1]; Version = [version]"$($Matches[2]).$($Matches[3]).$($Matches[4])"; Commit = $OriginRefs[$name] }
        }
    }
    return @($tags | Sort-Object Version) | Select-Object -Last 1
}

function Test-ProdCommitPresent {
    param([string]$Primary, [string]$Commit)
    & git -C $Primary cat-file -e "$Commit^{commit}" 2>$null
    return ($LASTEXITCODE -eq 0)
}

# The commit to deploy, and the proof that origin holds it. Without a ref it is
# the highest version tag on origin. A tag or branch name is read on origin, so
# a local main ahead of origin or a tag never pushed is not what ships. Any
# other ref must resolve to a commit some ref of origin contains.
function Resolve-ProdCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Primary,
        [string]$Ref
    )

    $fetch = @(& git -C $Primary fetch --quiet origin 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "git could not fetch origin in '$Primary': $($fetch -join ' ')" }
    $origin = Get-ProdOriginRefs -Primary $Primary

    $commit = $null; $source = $null
    if (-not $Ref) {
        $latest = Get-ProdLatestOriginTag -OriginRefs $origin
        if (-not $latest) { throw 'Origin carries no version tag vX.Y.Z: record one at the merge into main and push it, or pass -Ref.' }
        $Ref = $latest.Tag; $commit = $latest.Commit; $source = "refs/tags/$Ref"
    } elseif ($origin.Contains("refs/tags/$Ref")) {
        $commit = $origin["refs/tags/$Ref"]; $source = "refs/tags/$Ref"
    } elseif ($origin.Contains("refs/heads/$Ref")) {
        $commit = $origin["refs/heads/$Ref"]; $source = "refs/heads/$Ref"
    } else {
        $local = @(& git -C $Primary rev-parse --verify --quiet "$Ref^{commit}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or $local.Count -eq 0) { throw "No commit '$Ref' here or on origin." }
        $commit = $local[0].Trim()
        $held = $false
        foreach ($sha in @($origin.Values | Select-Object -Unique)) {
            if (-not (Test-ProdCommitPresent -Primary $Primary -Commit $sha)) { continue }
            & git -C $Primary merge-base --is-ancestor $commit $sha 2>$null
            if ($LASTEXITCODE -eq 0) { $held = $true; break }
        }
        if (-not $held) { throw "Commit $($commit.Substring(0, 7)) ('$Ref') is on no ref of origin: push it first, prod only ships what origin holds." }
    }

    # A tag on no fetched branch brings its objects only when asked by name;
    # into FETCH_HEAD, so no local tag is written or moved.
    if (-not (Test-ProdCommitPresent -Primary $Primary -Commit $commit)) {
        $log = @(& git -C $Primary fetch --quiet --no-tags origin $source 2>&1 | ForEach-Object { [string]$_ })
        if ($LASTEXITCODE -ne 0) { throw "git could not fetch $source from origin: $($log -join ' ')" }
    }

    # A version tag read on origin is the version, even when no local tag
    # of that name exists yet.
    $version = if ($source -match '^refs/tags/(v\d+\.\d+\.\d+)$') { $Matches[1] } else { Get-ProdVersion -Primary $Primary -Commit $commit }
    return [pscustomobject]@{
        Ref     = $Ref
        Commit  = $commit
        Version = $version
    }
}

# The version a commit is: its tag vX.Y.Z when it carries one, else git
# describe's vX.Y.Z-N-gSHA, the tag below it and how far past it.
function Get-ProdVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Primary,
        [Parameter(Mandatory)][string]$Commit
    )

    $lines = @(& git -C $Primary describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' --abbrev=7 $Commit 2>$null)
    if ($LASTEXITCODE -eq 0 -and $lines.Count -gt 0) { return $lines[0].Trim() }
    return "untagged-$($Commit.Substring(0, 7))"
}

# Runs one command of the settings in its own pwsh, in the snapshot, with the
# PROD_* variables set: a command that fails, or exits non-zero, fails the deploy.
function Invoke-ProdCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory)][string]$Name
    )

    $saved = @{}
    foreach ($key in $Environment.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key])
    }
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & pwsh -NoProfile -NonInteractive -Command $Command
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }
    if ($code -ne 0) { throw "The $Name command failed (exit code $code): $Command" }
}

# What a status reports for one repository: the slots, origin's latest version
# and how far the running build is behind origin's branch. A fetch that fails
# is reported, never thrown: the status still says what it knows.
function Get-ProdState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Primary,
        [string]$Root,
        [switch]$NoFetch
    )

    $settings = Read-ProdSettings -Primary $Primary
    $layout = Get-ProdLayout -Root (Resolve-ProdRoot -Primary $Primary -Settings $settings -Root $Root)
    $running = Read-ProdStamp -Folder $layout.Current
    $staged = Read-ProdStamp -Folder $layout.Next

    $originError = $null; $latest = $null; $behind = $null
    if (-not $NoFetch) {
        & git -C $Primary fetch --quiet origin 2>$null
        if ($LASTEXITCODE -ne 0) { $originError = 'origin could not be fetched; the figures below are from the last fetch' }
    }
    try {
        $latest = Get-ProdLatestOriginTag -OriginRefs (Get-ProdOriginRefs -Primary $Primary)
    } catch {
        $originError = 'origin could not be reached'
    }
    $tip = "refs/remotes/origin/$($settings.Branch)"
    if ($running -and (Test-ProdCommitPresent -Primary $Primary -Commit $running.commit)) {
        $count = @(& git -C $Primary rev-list --count "$($running.commit)..$tip" 2>$null)
        if ($LASTEXITCODE -eq 0 -and $count.Count -gt 0) { $behind = [int]$count[0] }
    }

    return [pscustomobject]@{
        Repository  = Split-Path -Leaf $Primary
        Primary     = $Primary
        Root        = $layout.Root
        Swap        = $settings.Swap
        Branch      = $settings.Branch
        Running     = Format-ProdSlot -Folder $layout.Current
        Staged      = Format-ProdSlot -Folder $layout.Next
        Previous    = Format-ProdSlot -Folder $layout.Previous
        RunningStamp = $running
        StagedStamp = $staged
        Latest      = if ($latest) { "$($latest.Tag) ($($latest.Commit.Substring(0, 7)))" } else { 'none' }
        LatestCommit = if ($latest) { $latest.Commit } else { $null }
        Behind      = $behind
        OriginError = $originError
    }
}

function Format-ProdBehind {
    param($State)
    if ($null -eq $State.Behind) { return 'unknown' }
    if ($State.Behind -eq 0) { return "up to date with origin/$($State.Branch)" }
    return "$($State.Behind) commit(s) behind origin/$($State.Branch)"
}
