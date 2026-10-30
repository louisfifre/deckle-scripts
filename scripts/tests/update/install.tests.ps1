$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fixture.ps1')
$InstallPath = Join-Path (Split-Path -Parent $script:RealScriptsDir) 'install.ps1'

# Windows PowerShell 5.1 reads this file: it must parse, stay ASCII and take no parameters.
$bytes = [IO.File]::ReadAllBytes($InstallPath)
Assert-True (-not ($bytes | Where-Object { $_ -gt 127 })) 'install.ps1 is pure ASCII'
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($InstallPath, [ref]$null, [ref]$parseErrors)
Assert-Equal 0 @($parseErrors).Count 'install.ps1 has no parse error'
Assert-True ($null -eq $ast.ParamBlock) 'install.ps1 has no param block, because iex cannot pass arguments'
$text = [Text.Encoding]::ASCII.GetString($bytes)
Assert-True ($text -notmatch '\?\?|GetRelativePath') 'install.ps1 uses no PowerShell 7 only syntax'
Assert-True ($text -match "(?m)^\`$SourceUrl = 'https://github\.com/louisfifre/deckle-scripts\.git'") 'the source URL is a variable at the top'

$root = Join-Path ([IO.Path]::GetTempPath()) "install-$([guid]::NewGuid())"
try {
    # Outside a repository it stops with one plain sentence.
    $plain = Join-Path $root 'plain'
    $null = New-Item -ItemType Directory -Path $plain
    Push-Location $plain
    try { $outside = Invoke-Script $InstallPath @() } finally { Pop-Location }
    Assert-True ($outside.ExitCode -ne 0) 'install.ps1 fails outside a git repository'
    Assert-True ($outside.Text -match 'inside the repository') 'install.ps1 says to run it inside the repository'

    # Against a local bare source (the one-line copy points $SourceUrl at it).
    $source = Join-Path $root 'source'
    New-SourceFixture $source
    $bare = Join-Path $root 'bare.git'
    Invoke-Git $source @('clone', '--quiet', '--bare', $source, $bare)
    $copy = Join-Path $root 'install-local.ps1'
    $local = $text -replace "(?m)^\`$SourceUrl = '[^']*'", ('$SourceUrl = ''' + $bare + '''')
    Assert-True ($local -ne $text) 'the test copy points at the local source'
    [IO.File]::WriteAllText($copy, $local)

    $target = Join-Path $root 'target'
    New-TargetFixture $target
    Push-Location $target
    try { $installed = Invoke-Script $copy @() } finally { Pop-Location }
    Assert-Equal 0 $installed.ExitCode 'install.ps1 installs as a file'
    Assert-True (Test-Path -LiteralPath (Join-Path $target 'scripts/menu.ps1')) 'the launcher is installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $target 'scripts/alpha/one.ps1')) 'the packs are installed'
    . (Join-Path $script:RealScriptsDir 'lib/manifest.ps1')
    $manifest = Read-InstallManifest -RepositoryRoot $target
    Assert-Equal '0.1.0' $manifest.version 'install.ps1 installs the latest tag'
    Assert-Equal $bare ([string]$manifest.source) 'install.ps1 records its source'
    Assert-True ($installed.Text -match 'Success') 'install.ps1 shows the summary of the update'

    # Through iex the shell must survive: no exit may close it.
    $iexTarget = Join-Path $root 'iex-target'
    New-TargetFixture $iexTarget
    Push-Location $iexTarget
    try {
        $viaIex = @(& pwsh -NoProfile -Command "Get-Content -Raw -LiteralPath '$copy' | Invoke-Expression; 'shell still alive'" 2>&1 6>&1) -join "`n"
        $viaIexCode = $LASTEXITCODE
    } finally { Pop-Location }
    Assert-Equal 0 $viaIexCode 'install through iex succeeds'
    Assert-True ($viaIex -match 'shell still alive') 'install through iex leaves the shell open'
    Assert-True (Test-Path -LiteralPath (Join-Path $iexTarget 'scripts/menu.ps1')) 'install through iex installs'

    # A second run on an installed repository changes nothing and still exits 0.
    Push-Location $target
    try { $rerun = Invoke-Script $copy @() } finally { Pop-Location }
    Assert-Equal 0 $rerun.ExitCode 'install.ps1 reruns without harm'
    Assert-True ($rerun.Text -match 'already up to date') 'a rerun says up to date'

    Write-Host 'install.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
