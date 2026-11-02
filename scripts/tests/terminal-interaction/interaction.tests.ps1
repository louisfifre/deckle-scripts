$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
Import-Module (Join-Path $LibDir 'terminal-interaction.psm1') -Force
. (Join-Path $ScriptsDir 'tests\fixtures\terminal-interaction\sample-views.ps1')

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function New-RunView([string]$State, [string[]]$Journal) {
    return New-TerminalExecutionView `
        -ViewId execution.sample `
        -Banner Sample `
        -State $State `
        -JournalLines $Journal `
        -TrackingSteps @([pscustomobject]@{ Label = 'Run'; State = $State }) `
        -OwnerActionMenuId menu.root
}

# An Execute decision hands its Runner a paint callback, and the Runner calls
# it from outside the module, as the launcher does.
$root = Get-SampleRootView
$started = New-RunView -State Running -Journal @('start')
$midway = New-RunView -State Running -Journal @('start', 'midway')
$finished = New-RunView -State Completed -Journal @('start', 'midway', 'done')
$decision = [pscustomobject]@{
    Kind = 'Execute'
    Mode = 'Open'
    View = $started
    Runner = {
        param($paint)
        & $paint $midway
        & $paint $finished
        return $finished
    }.GetNewClosure()
}

$module = Get-Module terminal-interaction
$run = & $module {
    param($rootView, $decision)

    # The console is the boundary: its size is fixed and its writes are
    # recorded, so the run is observed without a terminal.
    $writes = [System.Collections.Generic.List[object]]::new()
    function Get-TerminalHostMetrics { [pscustomobject]@{ Width = 100; Height = 30 } }
    function Clear-TerminalHostInput { param($State) }
    function Write-TerminalInteractionFrame {
        param($Frame, $HostState, $PreviousFrame)
        $writes.Add([pscustomobject]@{ Frame = $Frame; PreviousFrame = $PreviousFrame })
    }

    $viewStack = [System.Collections.Generic.List[object]]::new()
    $viewStack.Add((New-TerminalViewState -View $rootView))
    $null = Set-TerminalDecision -ViewStack $viewStack -Decision $decision
    $hostState = [pscustomobject]@{ UnicodeOutput = 'Supported'; Color = 'Supported' }
    $returned = Invoke-TerminalExecution -ViewStack $viewStack -Decision $decision -HostState $hostState -PreviousFrame $null
    [pscustomobject]@{ Writes = $writes; Returned = $returned; State = $viewStack[$viewStack.Count - 1] }
} $root $decision

Assert-Equal 3 $run.Writes.Count 'the run paints its opening View, then each View its Runner hands over'
Assert-True (@(ConvertTo-TerminalFrameText -Frame $run.Writes[2].Frame) -join "`n").Contains('done') 'the last paint shows the View the Runner handed over last'
Assert-Equal $null $run.Writes[0].PreviousFrame 'the opening paint compares against the frame given by the caller'
for ($index = 1; $index -lt $run.Writes.Count; $index++) {
    Assert-True ([object]::ReferenceEquals($run.Writes[$index - 1].Frame, $run.Writes[$index].PreviousFrame)) `
        "paint $index compares against the frame painted just before it"
}
Assert-True ([object]::ReferenceEquals($run.Writes[2].Frame, $run.Returned)) 'the run returns the frame left on screen'
Assert-Equal Completed $run.State.View.State 'the Execution View keeps the final View of the Runner'

Write-Host 'interaction.tests.ps1: PASS' -ForegroundColor Green
