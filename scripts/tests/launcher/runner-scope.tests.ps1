$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
$FixtureDir = Join-Path $ScriptsDir 'tests\fixtures\script-discovery'

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

# menu.ps1 calls the launcher with &, so its functions live in a script scope
# below the global one. pwsh -File runs a test in the global scope, where any
# closure would see them; the child scope below reproduces the menu's.
$run = & {
    param($libDir, $fixtureDir)

    Import-Module (Join-Path $libDir 'terminal-interaction.psm1') -Force
    Import-Module (Join-Path $libDir 'script-discovery.psm1') -Force
    . (Join-Path $libDir 'launcher\discovered-catalog.ps1')
    . (Join-Path $libDir 'launcher\execution.ps1')
    . (Join-Path $libDir 'launcher\logs.ps1')
    . (Join-Path $libDir 'launcher\flows.ps1')

    $catalog = Get-ScriptCatalog -Path $fixtureDir
    $context = New-LauncherContext -Catalog $catalog -Banner 'Fixture' -RepositoryRoot $fixtureDir -ScriptsRoot $fixtureDir
    $rootView = Get-LauncherRootView -Context $context
    $payload = [pscustomobject]@{
        ActionId = 'gamma.0'; Variant = $null; Label = 'Pack'; ScriptRelativePath = 'gamma.ps1'
        Arguments = ''; VariantParameter = $null; Confirmation = $null
    }
    $request = [pscustomobject]@{ TargetId = 'action.gamma.0'; IntentKind = 'Action'; Payload = $payload; SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $request -SourceView $rootView -Context $context
    $painted = [System.Collections.Generic.List[object]]::new()
    $final = & $decision.Runner { param($view) $painted.Add($view) }.GetNewClosure()
    [pscustomobject]@{ Final = $final; Painted = $painted.Count }
} $LibDir $FixtureDir

Assert-Equal 'Completed' $run.Final.State 'an Action runs to its end when the launcher lives below the global scope, as under menu.ps1'
Assert-Equal $true ($run.Painted -ge 1) 'the run paints through the callback from the menu scope'

Write-Host 'runner-scope.tests.ps1: PASS' -ForegroundColor Green
