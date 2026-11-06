$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptsDir 'lib\terminal-interaction.psm1') -Force
$module = Get-Module terminal-interaction

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

$bridgeAvailable = & $module { Initialize-TerminalHostBridge }
Assert-Equal $true $bridgeAvailable 'Windows console bridge compiles for this PowerShell engine'

$escape = [char]27
$origin = & $module { Get-TerminalCursorPositionSequence -X 0 -Y 0 }
$position = & $module { Get-TerminalCursorPositionSequence -X 7 -Y 3 }
Assert-Equal "$escape[1;1H" $origin 'terminal origin converts to one-based ANSI coordinates'
Assert-Equal "$escape[4;8H" $position 'terminal position converts row and column to ANSI coordinates'

function Get-SegmentColors([string]$Role, [string]$State, [object]$HostState) {
    & $module {
        param($role, $state, $hostState)
        Get-TerminalSegmentColors `
            -Segment ([pscustomobject]@{ PresentationRole = $role; State = $state }) `
            -HostState $hostState
    } $Role $State $HostState
}

function Get-SegmentSequence([int]$X, [int]$Y, [string]$Text, [object]$Colors) {
    & $module {
        param($x, $y, $text, $colors)
        Get-TerminalSegmentSequence `
            -X $x `
            -Y $y `
            -Text $text `
            -Foreground $colors.Foreground `
            -Background $colors.Background
    } $X $Y $Text $Colors
}

# The theme sends console colours only, whatever the console reports.
$terminalHost = [pscustomobject]@{
    Color = 'Supported'
    OriginalForeground = [ConsoleColor]::Gray
    OriginalBackground = [ConsoleColor]::Black
}
$lightConsoleHost = [pscustomobject]@{
    Color = 'Supported'
    OriginalForeground = [ConsoleColor]::Gray
    OriginalBackground = [ConsoleColor]::White
}
foreach ($hostState in @($terminalHost, $lightConsoleHost)) {
    $sectionColors = Get-SegmentColors -Role Section -State Normal -HostState $hostState
    Assert-Equal ([ConsoleColor]::Magenta) $sectionColors.Foreground 'a Section takes its console colour'
    Assert-Equal $null $sectionColors.Background 'a Section leaves the background to the terminal'
    # The console reports grey on black whatever the scheme shows, so a role
    # the theme leaves unnamed must not take the reported pair.
    $bodyColors = Get-SegmentColors -Role Body -State Normal -HostState $hostState
    Assert-Equal $null $bodyColors.Foreground 'body text leaves the foreground to the terminal'
    Assert-Equal $null $bodyColors.Background 'body text leaves the background to the terminal'
}
$terminalSection = Get-SegmentSequence -X 1 -Y 4 -Text 'RUN ' -Colors (Get-SegmentColors -Role Section -State Normal -HostState $terminalHost)
Assert-Equal "$escape[5;2H$escape[95;49mRUN " $terminalSection 'a Section emits its console foreground on the default background in one VT sequence'
$terminalBody = Get-SegmentSequence -X 1 -Y 5 -Text 'Builds' -Colors (Get-SegmentColors -Role Body -State Normal -HostState $terminalHost)
Assert-Equal "$escape[6;2H$escape[39;49mBuilds" $terminalBody 'body text emits the default foreground and background, never the reported console pair'
$resetAttributes = & $module { Get-TerminalTextAttributeSequence -Foreground $null -Background $null }
Assert-Equal "$escape[39;49m" $resetAttributes 'the frame closes on the terminal defaults'
$terminalActionFocus = Get-SegmentSequence -X 7 -Y 3 -Text '> Launch' -Colors (Get-SegmentColors -Role Action -State Focused -HostState $terminalHost)
Assert-Equal "$escape[4;8H$escape[30;47m> Launch" $terminalActionFocus 'a focused Action emits cursor, classic selection attributes, and content as one VT sequence'
$terminalExitFocus = Get-SegmentSequence -X 7 -Y 3 -Text '  Quit' -Colors (Get-SegmentColors -Role Exit -State Focused -HostState $terminalHost)
Assert-Equal "$escape[4;8H$escape[30;47m  Quit" $terminalExitFocus 'a focused Exit uses the classic ordinary selection treatment'
$terminalDangerFocus = Get-SegmentSequence -X 7 -Y 3 -Text '  Reset' -Colors (Get-SegmentColors -Role Danger -State Focused -HostState $terminalHost)
Assert-Equal "$escape[4;8H$escape[97;41m  Reset" $terminalDangerFocus 'a focused Danger target inverts to white on dark red'
$terminalCommandKey = Get-SegmentSequence -X 0 -Y 0 -Text 'Enter' -Colors (Get-SegmentColors -Role CommandKey -State Normal -HostState $terminalHost)
Assert-Equal "$escape[1;1H$escape[37;49mEnter" $terminalCommandKey 'a command key remains distinct from its muted command label'
$terminalCommandLabel = Get-SegmentSequence -X 6 -Y 0 -Text 'Open' -Colors (Get-SegmentColors -Role CommandLabel -State Normal -HostState $terminalHost)
Assert-Equal "$escape[1;7H$escape[90;49mOpen" $terminalCommandLabel 'a command label emits the classic muted foreground through the VT stream'
$noColorHost = [pscustomobject]@{
    Color = 'Unsupported'
    OriginalForeground = [ConsoleColor]::Gray
    OriginalBackground = [ConsoleColor]::Black
}
$noColorSection = Get-SegmentSequence -X 1 -Y 4 -Text 'RUN ' -Colors (Get-SegmentColors -Role Section -State Normal -HostState $noColorHost)
Assert-Equal "$escape[5;2H$escape[39;49mRUN " $noColorSection 'a host without colour support receives the terminal defaults only'

$action = New-TerminalTarget -TargetId action.sample -Label Sample -IntentKind Action
$otherAction = New-TerminalTarget -TargetId action.other -Label Other -IntentKind Action
$section = New-TerminalSection -Label Sample -Items @(New-TerminalActionRow -Label Test -Variants @($action, $otherAction))
$view = New-TerminalActionMenuView -ViewId menu.sample -Banner Sample -Sections @($section)
$frame = Get-TerminalInteractionFrame -View $view -Width 100 -Height 12 -FocusedTargetId action.sample
$snapshot = @(ConvertTo-TerminalFrameText -Frame $frame) -join "`n"
Assert-Equal $false $snapshot.Contains([string]$escape) 'redirectable frame text contains no cursor-control sequences'

$unchangedLines = @(& $module { param($current) Get-TerminalChangedLineIndexes -Frame $current -PreviousFrame $current } $frame)
Assert-Equal 0 $unchangedLines.Count 'an identical retained frame schedules no repaint'
$otherFocusedFrame = Get-TerminalInteractionFrame -View $view -Width 100 -Height 12 -FocusedTargetId action.other
$focusLines = @(& $module { param($current, $previous) Get-TerminalChangedLineIndexes -Frame $current -PreviousFrame $previous } $otherFocusedFrame $frame)
$focusLine = @($otherFocusedFrame.Targets | Where-Object { $_.TargetId -eq 'action.other' })[0].Y
Assert-Equal 1 $focusLines.Count 'focus movement schedules only the affected frame line'
Assert-Equal $focusLine $focusLines[0] 'focus movement schedules the line that contains both target states'
$resizedFrame = Get-TerminalInteractionFrame -View $view -Width 101 -Height 12 -FocusedTargetId action.other
$resizedLines = @(& $module { param($current, $previous) Get-TerminalChangedLineIndexes -Frame $current -PreviousFrame $previous } $resizedFrame $otherFocusedFrame)
Assert-Equal $resizedFrame.Lines.Count $resizedLines.Count 'a geometry change schedules a complete redraw'

Write-Host 'host.tests.ps1: PASS' -ForegroundColor Green
