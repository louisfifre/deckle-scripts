$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent $PSScriptRoot
$CommandPath = Join-Path $ScriptsDir 'check-scripts.ps1'
$FixtureDir = Join-Path $ScriptsDir 'tests\fixtures\script-discovery'

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Write-Utf8File([string]$Path, [string]$Content, [bool]$Bom) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($Bom))
}

$root = Join-Path ([IO.Path]::GetTempPath()) "check-scripts-$([guid]::NewGuid())"
try {
    $scriptsCopy = Join-Path $root 'scripts'
    $null = New-Item -ItemType Directory -Path $scriptsCopy
    Copy-Item -Path (Join-Path $FixtureDir '*') -Destination $scriptsCopy -Recurse
    # The entry, the library and the tests are exempt whatever they hold.
    $null = New-Item -ItemType Directory -Path (Join-Path $scriptsCopy 'lib')
    $null = New-Item -ItemType Directory -Path (Join-Path $scriptsCopy 'tests')
    Write-Utf8File (Join-Path $scriptsCopy 'lib\helper.ps1') "param([switch]`$Pick)`n" $true
    Write-Utf8File (Join-Path $scriptsCopy 'tests\sample.tests.ps1') "param([switch]`$Pick)`n" $true
    Write-Utf8File (Join-Path $scriptsCopy 'menu.ps1') "param([switch]`$Pick)`n" $true

    $faultyOutput = @(& pwsh -NoProfile -File $CommandPath -Target $root 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 1) 'voided and invalid headers fail the check'
    foreach ($name in @('glued-requires.ps1', 'dot-word.ps1', 'two-axes.ps1')) {
        Assert-True ($faultyOutput -match [regex]::Escape("scripts/$name")) "the faulty list names $name"
    }
    Assert-True ($faultyOutput -match 'scripts/no-header\.ps1') 'the hidden-by-choice list names the script without a Header'
    Assert-True ($faultyOutput -notmatch 'scripts/no-header\.ps1 \[') 'a script without a Header is not a fault'
    Assert-True ($faultyOutput -notmatch 'lib/helper|tests/sample|scripts/menu\.ps1') 'the entry, the library and the tests are exempt'
    Assert-True ($faultyOutput -match 'Faulty\s*:\s*3') 'the summary counts the faulty headers'

    foreach ($name in @('glued-requires.ps1', 'dot-word.ps1', 'two-axes.ps1')) {
        Remove-Item -LiteralPath (Join-Path $scriptsCopy $name) -Force
    }
    $cleanOutput = @(& pwsh -NoProfile -File $CommandPath -Target $root 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'scripts hidden by choice do not fail the check'
    Assert-True ($cleanOutput -match 'scripts/no-header\.ps1') 'hidden scripts are still listed when the check passes'
    Assert-True ($cleanOutput -match 'Hidden\s*:\s*1') 'the summary counts the hidden scripts'

    # The conventions a valid Header cannot tell.
    $header = "<#`n.SYNOPSIS`n    Convention`n.DESCRIPTION`n    Breaks a convention.`n#>`n"
    Write-Utf8File (Join-Path $scriptsCopy 'picks.ps1') "$header[CmdletBinding()]`nparam([switch]`$Pick)`n" $false
    Write-Utf8File (Join-Path $scriptsCopy 'typed-target.ps1') "$header[CmdletBinding()]`nparam([object]`$Target)`n" $false
    Write-Utf8File (Join-Path $scriptsCopy 'marked.ps1') "$header[CmdletBinding()]`nparam([string]`$Target)`n" $true
    $conventionOutput = @(& pwsh -NoProfile -File $CommandPath -Target $root 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 1) 'a broken convention fails the check'
    Assert-True ($conventionOutput -match 'scripts/picks\.ps1 declares -Pick') 'a -Pick parameter is reported'
    Assert-True ($conventionOutput -match 'scripts/typed-target\.ps1 declares -Target as System\.Object') 'an untyped -Target is reported'
    Assert-True ($conventionOutput -match 'scripts/marked\.ps1 starts with a byte order mark') 'a byte order mark is reported'
    Assert-True ($conventionOutput -notmatch 'scripts/beta\.ps1 ') 'a string -Target passes'
    Assert-True ($conventionOutput -match 'Faulty\s*:\s*3') 'the summary counts the convention faults'

    Write-Host 'check-scripts.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
