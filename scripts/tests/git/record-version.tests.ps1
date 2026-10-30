$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'git\record-version.ps1'

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Script([string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
}

function Add-Commit([string]$Repo, [string]$Subject) {
    & git -C $Repo -c user.name=Test -c user.email=test@example.invalid commit --quiet --allow-empty -m $Subject
    if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
}

function Get-TagNames([string]$Repo) {
    return @(& git -C $Repo tag --list)
}

$root = Join-Path ([IO.Path]::GetTempPath()) "record-version-$([guid]::NewGuid())"
try {
    $repo = Join-Path $root 'repo'
    $null = New-Item -ItemType Directory -Path $repo
    & git -C $repo init --quiet
    # The tag needs an identity, and the fixture must not depend on the one of
    # the machine running the test.
    & git -C $repo config user.name Test
    & git -C $repo config user.email test@example.invalid
    & git -C $repo config core.autocrlf false

    $noCommit = Invoke-Script @('-Target', $repo)
    Assert-True ($noCommit.Code -ne 0) 'a repository without a commit cannot record a version'
    Assert-True ($noCommit.Text -match 'no commit yet') 'the failure says the repository has no commit'

    Add-Commit $repo 'feat: first'

    $preview = Invoke-Script @('-Target', $repo)
    Assert-Equal 0 $preview.Code 'the preview succeeds'
    Assert-True ($preview.Text -match '0\.1\.0') 'the preview names the first version'
    Assert-True ($preview.Text -match 'git tag -a v0\.1\.0') 'the preview shows the exact tag command'
    Assert-Equal 0 (Get-TagNames $repo).Count 'the preview creates no tag'

    $applied = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-Equal 0 $applied.Code 'apply succeeds on a fresh repository'
    Assert-Equal 'tag' (& git -C $repo cat-file -t v0.1.0) 'the version is an annotated tag'
    Assert-Equal 'Version 0.1.0' (& git -C $repo tag --list v0.1.0 --format='%(contents:subject)') 'the tag message names the version'
    Assert-True ($applied.Text -match 'Pushed\s*:\s*no') 'the summary says the tag was not pushed'

    $again = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-True ($again.Code -ne 0) 'a second apply on the same commit fails'
    Assert-True ($again.Text -match 'already carries v0\.1\.0') 'the failure says HEAD already carries the version'
    Assert-Equal 1 (Get-TagNames $repo).Count 'the failed apply creates no tag'

    Add-Commit $repo 'feat: second'
    $minor = Invoke-Script @('-Target', $repo, '-Apply', '-Bump', 'minor')
    Assert-Equal 0 $minor.Code 'a minor bump succeeds'
    Assert-Equal 'tag' (& git -C $repo cat-file -t v0.2.0) 'the minor bump records v0.2.0'

    Add-Commit $repo 'fix: third'
    $patch = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-Equal 0 $patch.Code 'the default bump succeeds'
    Assert-Equal 'tag' (& git -C $repo cat-file -t v0.2.1) 'the default bump is a patch'

    Add-Commit $repo 'feat!: fourth'
    $major = Invoke-Script @('-Target', $repo, '-Apply', '-Bump', 'major')
    Assert-Equal 0 $major.Code 'a major bump succeeds'
    Assert-Equal 'tag' (& git -C $repo cat-file -t v1.0.0) 'a major bump resets minor and patch'

    Add-Commit $repo 'fix: fifth'
    $noOrigin = Invoke-Script @('-Target', $repo, '-Apply', '-Push')
    Assert-True ($noOrigin.Code -ne 0) '-Push without an origin fails'
    Assert-True ($noOrigin.Text -match 'origin') 'the failure names the missing origin'
    Assert-True ($null -eq (Get-TagNames $repo | Where-Object { $_ -eq 'v1.0.1' })) 'a missing origin leaves no tag behind'

    $dirty = Join-Path $repo 'tracked.txt'
    [IO.File]::WriteAllText($dirty, "one`n")
    & git -C $repo add tracked.txt
    Add-Commit $repo 'chore: track a file'
    [IO.File]::WriteAllText($dirty, "two`n")
    $dirtyRun = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-True ($dirtyRun.Code -ne 0) 'a dirty tracked file fails'
    Assert-True ($dirtyRun.Text -match 'tracked\.txt') 'the failure lists the dirty file'
    Assert-True ($null -eq (Get-TagNames $repo | Where-Object { $_ -eq 'v1.0.1' })) 'a dirty tree creates no tag'

    # With a reachable origin the tag travels with -Push.
    & git -C $repo checkout --quiet -- tracked.txt
    $remote = Join-Path $root 'remote.git'
    & git init --quiet --bare $remote
    & git -C $repo remote add origin $remote
    $pushed = Invoke-Script @('-Target', $repo, '-Apply', '-Push')
    Assert-Equal 0 $pushed.Code 'apply with -Push succeeds'
    Assert-True ($pushed.Text -match 'Pushed\s*:\s*yes') 'the summary says the tag was pushed'
    Assert-True (@(& git -C $remote tag --list v1.0.1).Count -eq 1) 'the remote received the tag'

    Write-Host 'record-version.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
