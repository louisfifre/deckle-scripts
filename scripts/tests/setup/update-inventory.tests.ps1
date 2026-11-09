$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'setup\update-inventory.ps1'

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-UpdateInventory([string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "update-inventory-$([guid]::NewGuid())"
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'scripts\tools'), (Join-Path $root 'scripts\lib'), (Join-Path $root 'scripts\tests')
    & git -C $root init --quiet

    [IO.File]::WriteAllText((Join-Path $root 'scripts\build.ps1'), @'
<#
.SYNOPSIS
    Build the app.
.DESCRIPTION
    Builds the app for the chosen configuration. Then it says so.
.NOTES
    action: Build |
    action: Wipe | -Apply | danger | Deletes everything.
#>
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$Apply
)
'build'
'@)
    [IO.File]::WriteAllText((Join-Path $root 'scripts\tools\locked.ps1'), @'
# locked.ps1 - Run one build under a lock,
# waiting for a free slot.
#
# More detail that stays in the script.
param([Parameter(Mandatory)][string]$Project)
'locked'
'@)
    [IO.File]::WriteAllText((Join-Path $root 'scripts\lib\helper.ps1'), "# helper.ps1 - A library.`n")
    [IO.File]::WriteAllText((Join-Path $root 'scripts\tests\a.tests.ps1'), "# a.tests.ps1 - A test.`n")
    [IO.File]::WriteAllText((Join-Path $root 'scripts\untracked.ps1'), "# untracked.ps1 - Never added.`n")
    & git -C $root add scripts/build.ps1 scripts/tools scripts/lib scripts/tests 2>$null
    $inventoryPath = Join-Path $root 'scripts\INVENTORY.md'

    $preview = Invoke-UpdateInventory @('-Target', $root)
    Assert-Equal 0 $preview.ExitCode 'the preview succeeds'
    Assert-True (-not (Test-Path -LiteralPath $inventoryPath)) 'the preview writes nothing'
    Assert-True ($preview.Text -match 'Scripts\s*:\s*2') 'lib, tests and untracked scripts are left out'

    $apply = Invoke-UpdateInventory @('-Target', $root, '-Apply')
    Assert-Equal 0 $apply.ExitCode 'apply succeeds'
    $bytes = [IO.File]::ReadAllBytes($inventoryPath)
    Assert-True ($bytes -notcontains 13) 'the inventory has LF line endings only'
    $text = [IO.File]::ReadAllText($inventoryPath)
    Assert-True ($text.Contains('- `build.ps1` — **Build the app.** Builds the app for the chosen configuration.')) 'a Header gives the label and the first sentence'
    Assert-True ($text.Contains('Wipe `-Apply` (danger)')) 'a danger action is marked with its arguments'
    Assert-True ($text.Contains('-Configuration Debug|Release')) 'the variant parameter lists its values'
    Assert-True ($text.Contains('- `tools/locked.ps1` — Run one build under a lock, waiting for a free slot. (not in the menu)')) 'a script without a Header is described by its first comment paragraph'
    Assert-True ($text.Contains('-Project <string> (required)')) 'a mandatory parameter is marked'
    Assert-True (-not $text.Contains('helper.ps1')) 'lib/ is left out'
    Assert-True ($text.IndexOf('## `scripts/`') -lt $text.IndexOf('## `scripts/tools/`')) 'the root folder comes first'

    $again = Invoke-UpdateInventory @('-Target', $root, '-Apply')
    Assert-True ($again.Text -match 'Changed\s*:\s*no') 'an unchanged set of scripts leaves the file as it is'

    Write-Host 'update-inventory.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
