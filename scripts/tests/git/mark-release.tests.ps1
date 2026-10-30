$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'git\mark-release.ps1'

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

$root = Join-Path ([IO.Path]::GetTempPath()) "mark-release-$([guid]::NewGuid())"
try {
    $repo = Join-Path $root 'repo'
    $null = New-Item -ItemType Directory -Path $repo
    & git -C $repo init --quiet
    & git -C $repo config user.name Test
    & git -C $repo config user.email test@example.invalid
    & git -C $repo commit --quiet --allow-empty -m 'feat: first'

    $noVersion = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-True ($noVersion.Code -ne 0) 'a commit without a version tag cannot be marked'
    Assert-True ($noVersion.Text -match 'carries no version tag') 'the failure is the version error'
    Assert-True (@(& git -C $repo tag --list 'release/*').Count -eq 0) 'the failed run creates no release tag'

    & git -C $repo tag -a v0.1.0 -m 'Version 0.1.0'

    $preview = Invoke-Script @('-Target', $repo)
    Assert-Equal 0 $preview.Code 'the preview succeeds'
    Assert-True ($preview.Text -match 'release/v0\.1\.0') 'the preview names the release tag'
    Assert-True (@(& git -C $repo tag --list 'release/*').Count -eq 0) 'the preview creates no tag'

    $applied = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-Equal 0 $applied.Code 'apply succeeds'
    Assert-Equal 'tag' (& git -C $repo cat-file -t release/v0.1.0) 'the release mark is an annotated tag'
    Assert-Equal 'Release 0.1.0' (& git -C $repo tag --list release/v0.1.0 --format='%(contents:subject)') 'the tag message names the release'
    Assert-Equal (& git -C $repo rev-parse 'v0.1.0^{commit}') (& git -C $repo rev-parse 'release/v0.1.0^{commit}') 'the release mark sits on the commit of the version'
    Assert-True ($applied.Text -match 'Pushed\s*:\s*no') 'the summary says the tag was not pushed'

    $again = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-True ($again.Code -ne 0) 'a second apply fails'
    Assert-True ($again.Text -match 'already exists') 'the failure says the mark exists'

    & git -C $repo commit --quiet --allow-empty -m 'fix: second'
    $remote = Join-Path $root 'remote.git'
    & git init --quiet --bare $remote
    & git -C $repo remote add origin $remote
    & git -C $repo tag -a v0.1.1 -m 'Version 0.1.1'
    $pushed = Invoke-Script @('-Target', $repo, '-Apply', '-Push')
    Assert-Equal 0 $pushed.Code 'apply with -Push succeeds'
    Assert-True ($pushed.Text -match 'Pushed\s*:\s*yes') 'the summary says the tag was pushed'
    Assert-True (@(& git -C $remote tag --list 'release/v0.1.1').Count -eq 1) 'the remote received the release tag'

    Write-Host 'mark-release.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
