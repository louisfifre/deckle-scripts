$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
. (Join-Path $LibDir 'version.ps1')

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-Throws([scriptblock]$Block, [string]$Pattern, [string]$Case) {
    try { & $Block } catch { if ($_.Exception.Message -match $Pattern) { return }; throw "${Case}: unexpected error '$($_.Exception.Message)'" }
    throw "${Case}: no error was thrown"
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('version-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    & git -C $fixture init --quiet
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit --quiet --allow-empty -m 'first'
    Assert-Throws { Get-RepositoryVersion -Path $fixture } 'carries no version tag' 'a commit without a tag has no version and says what to do'
    Assert-Equal $null (Get-LatestRepositoryVersion -Path $fixture) 'a repository without tags has no latest version'

    & git -C $fixture tag -a v0.9.0 -m 'Version 0.9.0'
    & git -C $fixture tag not-a-version
    Assert-Equal '0.9.0' (Get-RepositoryVersion -Path $fixture) 'the version is the tag without its v'
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit --quiet --allow-empty -m 'second'
    & git -C $fixture tag -a v0.10.0 -m 'Version 0.10.0'
    Assert-Equal '0.10.0' (Get-LatestRepositoryVersion -Path $fixture) 'versions sort numerically, not as text'
    Assert-Equal '0.9.0' (Get-RepositoryVersion -Path $fixture -Commit 'HEAD~1') 'a version is read at any commit'
    Assert-Equal 2 @(Get-RepositoryVersionTags -Path $fixture).Count 'only vX.Y.Z tags are versions'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

Write-Host 'version.tests.ps1: PASS' -ForegroundColor Green
