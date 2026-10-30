$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
$FixtureDir = Join-Path $ScriptsDir 'tests\fixtures\script-discovery'
Import-Module (Join-Path $LibDir 'terminal-interaction.psm1') -Force
Import-Module (Join-Path $LibDir 'script-discovery.psm1') -Force
. (Join-Path $LibDir 'launcher\discovered-catalog.ps1')
. (Join-Path $LibDir 'launcher\execution.ps1')
. (Join-Path $LibDir 'launcher\logs.ps1')
. (Join-Path $LibDir 'launcher\flows.ps1')

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Get-JournalText([object]$Record) {
    return (@($Record.Journal | ForEach-Object { $_.Text }) -join "`n")
}

$root = Join-Path ([IO.Path]::GetTempPath()) "launcher-execution-$([guid]::NewGuid())"
try {
    $scriptsRoot = Join-Path $root 'scripts'
    $null = New-Item -ItemType Directory -Path $scriptsRoot
    Copy-Item -Path (Join-Path $FixtureDir '*') -Destination $scriptsRoot -Recurse
    $header = "<#`n.SYNOPSIS`n    {0}`n.DESCRIPTION`n    Fixture.`n#>`n"
    # A script that leaves through exit: the launcher must survive it and
    # read the code.
    [IO.File]::WriteAllText((Join-Path $scriptsRoot 'leaves.ps1'), ($header -f 'Leaves') + "Write-Output 'before'`nexit 3`n")
    # A script that throws: the failure reaches the Journal, not the host.
    [IO.File]::WriteAllText((Join-Path $scriptsRoot 'throws.ps1'), ($header -f 'Throws') + "throw 'boom'`n")
    # A script that reports through the output library.
    $reports = @(
        ($header -f 'Reports')
        ". (Join-Path '$($LibDir -replace "'", "''")' 'action-summary.ps1')"
        "Write-Output (Get-Location).Path"
        "Write-ActionSummary -Workflow 'Reports' -Result Partial -Sentence 'Half done.'"
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $scriptsRoot 'reports.ps1'), $reports)

    $catalog = Get-ScriptCatalog -Path $scriptsRoot
    $context = New-LauncherContext -Catalog $catalog -Banner 'Fixture' -RepositoryRoot $root -ScriptsRoot $scriptsRoot
    $rootView = Get-LauncherRootView -Context $context

    function Get-ActionPayload([string]$ActionId, [string]$Variant) {
        foreach ($section in $rootView.Sections) {
            foreach ($item in $section.Items) {
                $targets = if ($item.PSObject.Properties['Kind'] -and $item.Kind -eq 'ActionRow') { $item.Variants } else { @($item) }
                foreach ($target in $targets) {
                    if ($target.IntentKind -eq 'Action' -and $target.Payload.ActionId -eq $ActionId -and (-not $Variant -or $target.Payload.Variant -eq $Variant)) {
                        return $target.Payload
                    }
                }
            }
        }
        throw "No Action '$ActionId' in the fixture root."
    }

    # A plain run captures the script's output and ends in Success.
    $paints = 0
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'gamma.0') -OwnerActionMenuId $rootView.ViewId -Sequence 1
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root -Publish { param($r) $script:paints++ }
    Assert-Equal 'Completed' $record.State 'a script that returns completes'
    Assert-Equal 'Success' $record.Result 'a script without a summary nor a code succeeds'
    Assert-True ((Get-JournalText $record) -match 'gamma False') 'the script output reaches the Journal'
    Assert-Equal 'Supporting' $record.Journal[0].PresentationRole 'the command line opens the Journal as supporting text'
    Assert-True ($record.Journal[0].Text -match "gamma\.ps1'$") 'the command line names the script'
    Assert-True ($paints -ge 2) 'the run is published at least at its start and its end'

    # A Variant is passed to the script's parameter.
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'beta.0' 'Debug') -OwnerActionMenuId $rootView.ViewId -Sequence 2
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root
    Assert-True ($record.Journal[0].Text -match "-Configuration 'Debug'$") 'the Variant goes through its parameter'
    Assert-True ((Get-JournalText $record) -match 'beta Debug') 'the script receives the Variant'
    Assert-Equal 'Beta build / Debug' $record.Context 'the Context names the Action and its Variant'

    # The Header's arguments are passed as written.
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'gamma.1') -OwnerActionMenuId $rootView.ViewId -Sequence 3
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root
    Assert-True ((Get-JournalText $record) -match 'gamma True') 'the Header arguments reach the script'

    # exit inside the script neither ends the launcher nor hides the code.
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'leaves.0') -OwnerActionMenuId $rootView.ViewId -Sequence 4
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root
    Assert-Equal 'Failed' $record.State 'a non-zero exit code fails the run'
    Assert-Equal 'Failed with exit code 3' $record.Result 'the exit code is reported'
    Assert-True ((Get-JournalText $record) -match 'before') 'the output before exit is kept'

    # A thrown error is a failure of the run, written in the Journal.
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'throws.0') -OwnerActionMenuId $rootView.ViewId -Sequence 5
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root
    Assert-Equal 'Failed' $record.State 'a thrown error fails the run'
    Assert-True ($record.Result -match 'boom') 'the error message is the result'
    Assert-True (@($record.Journal | Where-Object { $_.PresentationRole -eq 'Error' }).Count -ge 1) 'the error is an Error line of the Journal'

    # The script's own summary is the conclusion, and it runs under the
    # repository root.
    $locationBefore = (Get-Location).Path
    $record = New-LauncherExecutionRecord -Action (Get-ActionPayload 'reports.0') -OwnerActionMenuId $rootView.ViewId -Sequence 6
    $record = Invoke-LauncherExecution -Record $record -ScriptsRoot $scriptsRoot -RepositoryRoot $root
    Assert-Equal 'Partial' $record.Result 'the reported Result is the conclusion'
    Assert-Equal 'Completed' $record.State 'a Partial run is complete'
    Assert-True ((Get-JournalText $record) -match [regex]::Escape($root)) 'the script runs under the repository root'
    Assert-Equal $locationBefore (Get-Location).Path 'the location is restored after the run'

    # The Execution View follows the record and renders.
    $view = ConvertTo-LauncherExecutionView -Record $record -Banner 'Fixture'
    Assert-Equal 'execution.reports.0.6' $view.ViewId 'the View is named after the Action and the sequence'
    $frame = Get-TerminalInteractionFrame -View $view -OwnerActionMenu $rootView -Width 100 -Height 30 -JournalOffset ([int]::MaxValue)
    $text = @(ConvertTo-TerminalFrameText -Frame $frame) -join "`n"
    Assert-True ($text -match 'Result: Partial') 'the Tracking Panel shows the conclusion'
    Assert-True ($text -match 'Half done') 'the Journal shows the summary sentence'

    # Intent resolution: a plain Action executes at once, a Danger Action
    # confirms first and then replaces the step by its run.
    $quit = [pscustomobject]@{ TargetId = 'command.quit'; IntentKind = 'Command'; Payload = $null; SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    Assert-Equal 'Exit' (Resolve-LauncherIntent -Request $quit -SourceView $rootView -Context $context).Kind 'Quit exits'

    $plain = [pscustomobject]@{ TargetId = 'action.gamma.0'; IntentKind = 'Action'; Payload = (Get-ActionPayload 'gamma.0'); SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $plain -SourceView $rootView -Context $context
    Assert-Equal 'Execute' $decision.Kind 'a plain Action is an Execute decision'
    Assert-Equal 'Open' $decision.Mode 'a plain Action opens its run over the menu'
    Assert-Equal 'Running' $decision.View.State 'the View starts in the Running state'
    $painted = [System.Collections.Generic.List[object]]::new()
    $final = & $decision.Runner { param($v) $painted.Add($v) }
    Assert-Equal 'Completed' $final.State 'the runner answers with the final View'
    Assert-True ($painted.Count -ge 1) 'the runner paints through the callback'
    Assert-Equal 1 $context.Logs.Records.Count 'the run is registered in the Logs'

    $danger = [pscustomobject]@{ TargetId = 'action.gamma.1'; IntentKind = 'Action'; Payload = (Get-ActionPayload 'gamma.1'); SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $danger -SourceView $rootView -Context $context
    Assert-Equal 'OpenView' $decision.Kind 'a Danger Action opens its Confirmation step'
    Assert-True (Test-LauncherConfirmationView -View $decision.View) 'the opened View is the Confirmation step'
    $confirmed = [pscustomobject]@{ TargetId = $decision.View.Targets[1].TargetId; IntentKind = 'Action'; Payload = $decision.View.Targets[1].Payload; SourceViewId = $decision.View.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $confirmed -SourceView $decision.View -Context $context
    Assert-Equal 'Execute' $decision.Kind 'the Danger choice executes'
    Assert-Equal 'Replace' $decision.Mode 'the run replaces the Confirmation step'
    Assert-Equal $rootView.ViewId $decision.View.OwnerActionMenuId 'the run stays owned by the menu that offered the Action'
    $null = & $decision.Runner {}
    Assert-Equal 2 $context.Logs.Records.Count 'each run is registered once'

    # The Logs list the runs and reopen one under the root menu.
    $logs = [pscustomobject]@{ TargetId = 'access.logs'; IntentKind = 'Access'; Payload = [pscustomobject]@{ AccessId = 'logs' }; SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $logs -SourceView $rootView -Context $context
    Assert-Equal 'OpenView' $decision.Kind 'the Logs open as a View'
    Assert-Equal 2 @($decision.View.Targets | Where-Object { $_.IntentKind -eq 'Access' }).Count 'the Logs offer each run'
    Assert-True ($decision.View.Targets[0].Label -match 'Pack') 'a run is labelled by its Context'
    $reopen = [pscustomobject]@{ TargetId = $decision.View.Targets[1].TargetId; IntentKind = 'Access'; Payload = $decision.View.Targets[1].Payload; SourceViewId = $decision.View.ViewId; Activation = 'Enter' }
    $reopened = Resolve-LauncherIntent -Request $reopen -SourceView $decision.View -Context $context
    Assert-Equal 'OpenView' $reopened.Kind 'a logged run reopens as a View'
    Assert-Equal 'Execution' $reopened.View.Kind 'the reopened run is an Execution View'
    Assert-Equal $rootView.ViewId $reopened.View.OwnerActionMenuId 'a reopened run sits under the menu that owns the Logs'
    Assert-Equal 'Completed' $reopened.View.State 'the reopened run shows its final state'

    # Folders become Accesses, empty ones are not offered.
    $access = [pscustomobject]@{ TargetId = 'access.tools'; IntentKind = 'Access'; Payload = [pscustomobject]@{ AccessId = 'tools' }; SourceViewId = $rootView.ViewId; Activation = 'Enter' }
    $decision = Resolve-LauncherIntent -Request $access -SourceView $rootView -Context $context
    Assert-Equal 'menu.discovered.tools' $decision.View.ViewId 'an Access opens its level'

    Write-Host 'execution.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
