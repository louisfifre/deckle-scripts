$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
Import-Module (Join-Path $LibDir 'script-discovery.psm1') -Force

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

# The menu entries of the maintenance pack: what each script declares is what
# the launcher shows, so a voided Header would silently drop the entry.
$clean = Read-ScriptHeader -Path (Join-Path $ScriptsDir 'maintenance\clean.ps1')
Assert-Equal 'Described' $clean.Status 'clean has a valid Header'
Assert-Equal 2 @($clean.Actions).Count 'clean declares a preview and a clean action'
Assert-Equal 'Preview|build outputs' "$($clean.Actions[0].Row)|$($clean.Actions[0].Cell)" 'the preview is the build outputs cell of the Preview row'
Assert-Equal 'Clean|build outputs' "$($clean.Actions[1].Row)|$($clean.Actions[1].Cell)" 'the clean is the build outputs cell of the Clean row'
Assert-Equal $false $clean.Actions[0].Danger 'the preview is not a danger action'
Assert-Equal '' $clean.Actions[0].Arguments 'the preview passes no argument'
Assert-Equal $true $clean.Actions[1].Danger 'the clean action is a danger action'
Assert-Equal '-Apply' $clean.Actions[1].Arguments 'the clean action applies'
Assert-Equal $null $clean.VariantParameter 'clean has no Variant axis'

$reset = Read-ScriptHeader -Path (Join-Path $ScriptsDir 'maintenance\reset-agent-state.ps1')
Assert-Equal 'Described' $reset.Status 'reset-agent-state has a valid Header'
Assert-Equal 2 @($reset.Actions).Count 'reset-agent-state declares an inspect and a reset action'
Assert-Equal 'Preview|Clean' "$($reset.Actions[0].Row)|$($reset.Actions[1].Row)" 'the AI sessions join the Preview and Clean rows'
Assert-Equal $true $reset.Actions[1].Danger 'the reset is a danger action'
Assert-Equal "-Apply -Confirmation 'RESET LOCAL AI SESSIONS'" $reset.Actions[1].Arguments 'the reset passes the confirmation phrase'
Assert-Equal $null $reset.VariantParameter 'the array-typed Scope filter gives no Variant'

Write-Host 'headers.tests.ps1: PASS' -ForegroundColor Green
