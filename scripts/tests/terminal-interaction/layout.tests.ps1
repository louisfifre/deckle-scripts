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

function Get-Placement([object]$Frame, [string]$TargetId) {
    $match = @($Frame.Targets | Where-Object { $_.TargetId -eq $TargetId })
    if ($match.Count -ne 1) { throw "placement '$TargetId': expected one match, got $($match.Count)" }
    return $match[0]
}

function Get-RoleLineIndex([object]$Frame, [string]$PresentationRole) {
    $matches = @(
        for ($lineIndex = 0; $lineIndex -lt $Frame.Lines.Count; $lineIndex++) {
            if (@($Frame.Lines[$lineIndex].Segments | Where-Object { $_.PresentationRole -eq $PresentationRole }).Count -gt 0) {
                $lineIndex
            }
        }
    )
    if ($matches.Count -ne 1) { throw "role '$PresentationRole': expected one line, got $($matches.Count)" }
    return $matches[0]
}

$root = Get-SampleRootView
$wide = Get-TerminalInteractionFrame -View $root -Width 100 -Height 24 -FocusedTargetId action.launch.release
$wideText = @(ConvertTo-TerminalFrameText -Frame $wide)
Assert-Equal 1 (Get-RoleLineIndex -Frame $wide -PresentationRole PrimarySeparator) 'the rule follows the root title line at once'
Assert-True ($wideText[0] -match '^  Deckle Scripts\s+.*Enter Open') 'the root title line carries the banner and the commands'
$launchRelease = Get-Placement -Frame $wide -TargetId action.launch.release
$launchDebug = Get-Placement -Frame $wide -TargetId action.launch.debug
Assert-Equal $launchRelease.Y $launchDebug.Y 'Action Variants share their Action Row in a wide terminal'
Assert-True ($launchRelease.X -lt $launchDebug.X) 'Release precedes Debug without semantic reordering'
$runHeading = @($wide.Lines | ForEach-Object { $_.Segments } | Where-Object { $_.PresentationRole -eq 'Section' -and $_.Text -eq 'RUN ' })[0]
$launchSubject = @($wide.Lines | ForEach-Object { $_.Segments } | Where-Object { $_.PresentationRole -eq 'ActionLabel' -and $_.Text -eq 'Launch' })[0]
Assert-Equal ($runHeading.X + 2) $launchSubject.X 'Action Row subjects keep two cells of indentation beneath their Section'

$maintenance = Get-Placement -Frame $wide -TargetId access.maintenance
$setup = Get-Placement -Frame $wide -TargetId access.setup
$releaseAccess = Get-Placement -Frame $wide -TargetId access.release
$quit = Get-Placement -Frame $wide -TargetId command.quit
Assert-Equal $setup.Y $quit.Y 'Quit seats on the last line of the menu, beside the last Access'
Assert-True ($maintenance.X -lt $setup.X -and $setup.X -lt $quit.X) 'Accesses and Quit keep their declared order'
Assert-Equal $releaseAccess.X $setup.X 'Release and Setup share the second option column'
Assert-Equal 98 ($quit.X + $quit.Width) 'Quit ends on the right rail of a 100-column frame'
Assert-True (($setup.X + $setup.Width) -le ($quit.X - 2)) 'the cell beside Quit is shortened so it stops before it'
Assert-True (($launchDebug.X + $launchDebug.Width) -gt $quit.X) 'Quit reserves nothing: the other rows run to the right rail'
Assert-Equal $launchDebug.X $setup.X 'the shortened cell keeps its column'
Assert-Equal 0 @($wide.Targets | Where-Object { $_.TargetId -like 'navigation.page.*' }).Count 'a fitting menu has no paging controls'
Assert-True (($wideText -join "`n") -match 'Enter Open') 'global command indications are visible in the Header'
Assert-True (($wideText -join "`n") -notmatch 'Backspace Back') 'the root menu does not advertise Back'
Assert-True (($wideText -join "`n") -match 'Escape Quit') 'the root menu advertises Escape as launcher exit'
$arrowLegend = -join @([char]0x2191, [char]0x2193, [char]0x2190, [char]0x2192)
Assert-True (($wideText -join "`n").Contains($arrowLegend)) 'Unicode-capable output preserves the arrow command key'

$asciiFallback = Get-TerminalInteractionFrame -View $root -Width 100 -Height 24 -FocusedTargetId action.launch.release -SupportsUnicode $false
$asciiFallbackText = @(ConvertTo-TerminalFrameText -Frame $asciiFallback) -join "`n"
Assert-True ($asciiFallbackText -match 'Arrows Move') 'an output host without Unicode receives an explicit ASCII key label'
Assert-Equal $false $asciiFallbackText.Contains($arrowLegend) 'the ASCII fallback emits no unsupported arrow glyph'

$narrow = Get-TerminalInteractionFrame -View $root -Width 60 -Height 30 -FocusedTargetId action.launch.release
$narrowRelease = Get-Placement -Frame $narrow -TargetId action.launch.release
$narrowDebug = Get-Placement -Frame $narrow -TargetId action.launch.debug
Assert-True ($narrowRelease.Y -lt $narrowDebug.Y) 'Action Variants stack in declared order in a narrow terminal'
Assert-Equal 11 @($narrow.Targets | Where-Object { $_.TargetId -notlike 'navigation.page.*' }).Count 'all root targets remain reachable at narrow width'
foreach ($line in @(ConvertTo-TerminalFrameText -Frame $narrow -PreserveWidth)) {
    Assert-Equal 60 $line.Length 'narrow frame lines honor terminal width'
}

$shortFirst = Get-TerminalInteractionFrame -View $root -Width 60 -Height 14 -FocusedTargetId action.launch.release
$nextPage = Get-Placement -Frame $shortFirst -TargetId navigation.page.next
Assert-Equal $true $nextPage.Target.Enabled 'a short first page exposes an enabled Next target'
$shortFirstText = @(ConvertTo-TerminalFrameText -Frame $shortFirst) -join "`n"
Assert-True ($shortFirstText -match 'Wheel Scroll') 'scrolling commands appear only in the paging footer'
Assert-True ($shortFirstText -match '- Previous') 'an unavailable page direction uses a neutral structural marker'
Assert-True ($shortFirstText -notmatch 'x Previous') 'a page boundary is not presented as an error'
$rootPagingSeparator = Get-RoleLineIndex -Frame $shortFirst -PresentationRole PagingSeparator
Assert-Equal ($rootPagingSeparator + 1) $nextPage.Y 'the paging separator frames the controls beneath the paged content'

$shortLast = Get-TerminalInteractionFrame -View $root -Width 60 -Height 14 -BodyOffset ([int]::MaxValue) -FocusedTargetId navigation.page.previous
$previousPage = Get-Placement -Frame $shortLast -TargetId navigation.page.previous
Assert-Equal $true $previousPage.Target.Enabled 'a later page exposes an enabled Previous target'
Assert-Equal 1 @($shortLast.Targets | Where-Object { $_.TargetId -eq 'command.quit' }).Count 'the final page makes Quit reachable'

$project = Get-SampleProjectView
$projectFrame = Get-TerminalInteractionFrame -View $project -Width 100 -Height 24 -FocusedTargetId navigation.back
$projectText = @(ConvertTo-TerminalFrameText -Frame $projectFrame) -join "`n"
Assert-Equal 1 (Get-RoleLineIndex -Frame $projectFrame -PresentationRole PrimarySeparator) 'a nested Header adds no line for its place'
$projectTitle = @(ConvertTo-TerminalFrameText -Frame $projectFrame)[0]
Assert-True ($projectTitle -match '^  Deckle Scripts > Project\s+.*Escape Back') 'the place follows the banner after a chevron, the commands at the end of the line'
$projectBack = Get-Placement -Frame $projectFrame -TargetId navigation.back
$readmePulse = Get-Placement -Frame $projectFrame -TargetId action.readme-stats
Assert-Equal $readmePulse.X $projectBack.X 'Back occupies the first option column instead of the label column'
Assert-True ($projectText -match 'Backspace Back') 'a nested View advertises Backspace'
Assert-True ($projectText -match 'Escape Back') 'a nested View advertises Escape as one-View navigation'

$preparation = Get-SampleSnapshotView -Name Preparation
$maintenanceView = Get-SampleMaintenanceView
$maintenanceFrame = Get-TerminalInteractionFrame -View $maintenanceView -Width 100 -Height 48 -FocusedTargetId action.repository-stats
$maintenanceText = @(ConvertTo-TerminalFrameText -Frame $maintenanceFrame) -join "`n"
$repositoryStatistics = Get-Placement -Frame $maintenanceFrame -TargetId action.repository-stats
$contextStatistics = Get-Placement -Frame $maintenanceFrame -TargetId action.context-stats
$cleanBuildOutputs = Get-Placement -Frame $maintenanceFrame -TargetId action.clean
$stopBuildServers = Get-Placement -Frame $maintenanceFrame -TargetId action.build-servers
$inspectAiSessions = Get-Placement -Frame $maintenanceFrame -TargetId action.inspect-agent-state
$resetAiSessions = Get-Placement -Frame $maintenanceFrame -TargetId action.reset-agent-state
Assert-Equal 3 $maintenanceView.Sections.Count 'Maintenance keeps its three semantic groups'
$maintenanceItems = @($maintenanceView.Sections | ForEach-Object { $_.Items })
Assert-Equal 6 $maintenanceItems.Count 'Maintenance keeps six independently activatable targets'
Assert-Equal 0 @($maintenanceItems | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ActionRow' }).Count 'nested Sections do not reclassify independent Actions as Action Rows'
Assert-Equal Action $maintenanceItems[0].IntentKind 'Repository statistics remains an independent Action intent'
Assert-Equal Action $maintenanceItems[0].PresentationRole 'the semantic target remains an Action before layout projection'
$maintenanceSegments = @($maintenanceFrame.Lines | ForEach-Object { $_.Segments })
Assert-Equal 0 @($maintenanceSegments | Where-Object { $_.PresentationRole -eq 'Section' }).Count 'a nested menu draws no Section heading'
Assert-Equal 0 @($maintenanceSegments | Where-Object { $_.PresentationRole -eq 'SectionSeparator' }).Count 'a nested menu draws no Section rule'
Assert-Equal 0 @($maintenanceSegments | Where-Object { $_.Text -eq 'Statistics' }).Count 'a nested Section label titles nothing'
Assert-Equal 1 @($maintenanceSegments | Where-Object { $_.Text -match 'Repository statistics' -and $_.PresentationRole -eq 'Action' }).Count 'an independent Action keeps its Action role'
Assert-Equal 1 @($maintenanceSegments | Where-Object { $_.Text -match 'Reset AI session state' -and $_.PresentationRole -eq 'Danger' }).Count 'danger survives in a nested Section'
Assert-Equal $repositoryStatistics.Y $contextStatistics.Y 'the Actions of one nested Section fill one line'
Assert-Equal $cleanBuildOutputs.Y $stopBuildServers.Y 'cleanup Actions fill one line'
Assert-Equal $inspectAiSessions.Y $resetAiSessions.Y 'AI-session Actions fill one line'
Assert-Equal ($repositoryStatistics.Y + 1) $cleanBuildOutputs.Y 'nested Sections follow one another without a gap'
Assert-Equal ($cleanBuildOutputs.Y + 1) $inspectAiSessions.Y 'every nested Section follows the previous one without a gap'
Assert-Equal $repositoryStatistics.X $cleanBuildOutputs.X 'first Maintenance Actions share one stable option track'
Assert-Equal $contextStatistics.X $stopBuildServers.X 'second Maintenance Actions share one stable option track'
Assert-True ($maintenanceText -match 'Repository statistics\s+Context statistics') 'the Actions of a nested Section keep their complete labels'
$preparationWide = Get-TerminalInteractionFrame `
    -View $preparation `
    -OwnerActionMenu $maintenanceView `
    -Width 100 `
    -Height 48 `
    -FocusedTargetId $preparation.DefaultTargetId
$preparationBack = Get-Placement -Frame $preparationWide -TargetId navigation.back
Assert-Equal $repositoryStatistics.X $preparationBack.X 'Preparation Back inherits the first option track of its owning Action Menu'
Assert-Equal $repositoryStatistics.Width $preparationBack.Width 'Preparation Back inherits the option-cell width of its owning Action Menu'
$preparationNarrow = Get-TerminalInteractionFrame -View $preparation -OwnerActionMenu $maintenanceView -Width 60 -Height 24 -FocusedTargetId $preparation.DefaultTargetId
$preparationNarrowText = @(ConvertTo-TerminalFrameText -Frame $preparationNarrow) -join "`n"
Assert-Equal 1 (Get-RoleLineIndex -Frame $preparationNarrow -PresentationRole PrimarySeparator) 'a narrow Header never grows beyond its title line'
$preparationNarrowTitle = @(ConvertTo-TerminalFrameText -Frame $preparationNarrow)[0]
Assert-True ($preparationNarrowTitle -match "^  Deckle Scripts > M[^ ]*$([char]0x2026)") 'a narrow Header shortens the breadcrumb, never the banner'
Assert-True ($preparationNarrowText -match 'Enter Select') 'narrow command priority preserves activation'
Assert-True ($preparationNarrowText -match 'Space Toggle') 'narrow command priority preserves selection editing'
Assert-True ($preparationNarrowText -notmatch 'Backspace Back') 'narrow command priority drops the least needed indications first'

$runningExecution = New-TerminalExecutionView `
    -ViewId execution.running `
    -Banner Running `
    -Context 'Build / Release' `
    -State Running `
    -JournalLines @('waiting') `
    -TrackingSteps @([pscustomobject]@{ Label = 'Build'; State = 'Running' }) `
    -BackTarget $project.BackTarget `
    -OwnerActionMenuId menu.root
$runningFrame = Get-TerminalInteractionFrame -View $runningExecution -OwnerActionMenu $root -Width 60 -Height 20 -FocusedTargetId navigation.back
$runningText = @(ConvertTo-TerminalFrameText -Frame $runningFrame) -join "`n"
Assert-True ($runningText -match 'Ctrl\+C Quit') 'a running Execution keeps emergency exit discoverable'
Assert-True ($runningText -notmatch 'Enter Open|Backspace Back|Escape Back') 'a running Execution advertises no unavailable command'

$execution = Get-SampleSnapshotView -Name Execution
$executionAlignment = Get-TerminalInteractionFrame -View $execution -OwnerActionMenu $root -Width 100 -Height 24 -FocusedTargetId navigation.back -JournalOffset ([int]::MaxValue)
$executionBack = Get-Placement -Frame $executionAlignment -TargetId navigation.back
Assert-Equal $launchRelease.X $executionBack.X 'Execution Back inherits the first option track of its owning Action Menu'
Assert-Equal $launchRelease.Width $executionBack.Width 'Execution Back inherits the option-cell width of its owning Action Menu'
$executionWide = Get-TerminalInteractionFrame -View $execution -OwnerActionMenu $root -Width 120 -Height 24 -FocusedTargetId navigation.back -JournalOffset ([int]::MaxValue)
$executionWideText = @(ConvertTo-TerminalFrameText -Frame $executionWide)
$panelTitleLine = @($executionWideText | Where-Object { $_ -match 'Execution Journal' -and $_ -match 'Execution Tracking' })
Assert-Equal 1 $panelTitleLine.Count 'wide Execution presents Journal and Tracking side by side'
Assert-True ($panelTitleLine[0].IndexOf('Execution Tracking') -gt 90) 'wide Tracking occupies the compact right-hand region'
Assert-Equal 1 @($executionWideText | Where-Object { $_ -match 'deliberately long line' }).Count 'a long Journal line is clipped without wrapping'
$panelTitleFrameLine = @(
    $executionWide.Lines | Where-Object {
        @($_.Segments | Where-Object { $_.Text -eq 'Execution Journal' }).Count -eq 1 -and
        @($_.Segments | Where-Object { $_.Text -eq 'Execution Tracking' }).Count -eq 1
    }
)
Assert-Equal 1 $panelTitleFrameLine.Count 'wide Panel titles share one stable title rail'
$wideResultText = @(
    foreach ($line in $executionWide.Lines) {
        foreach ($segment in $line.Segments) {
            if ($segment.PresentationRole -eq 'Success') { $segment.Text }
        }
    }
) -join ' '
Assert-Equal 'Result: Preview only; no repository changes.' $wideResultText 'wide Tracking wraps the complete Result instead of clipping it'
Assert-True (@($panelTitleFrameLine[0].Segments | Where-Object { $_.PresentationRole -eq 'PanelSeparator' }).Count -eq 1) 'wide Panel framing separates the title rail'
$widePanelSeparator = @($panelTitleFrameLine[0].Segments | Where-Object { $_.PresentationRole -eq 'PanelSeparator' })[0]
$widePrevious = Get-Placement -Frame $executionWide -TargetId navigation.page.previous
$wideNext = Get-Placement -Frame $executionWide -TargetId navigation.page.next
Assert-True (($widePrevious.X + $widePrevious.Width) -le $widePanelSeparator.X) 'wide Previous stays inside the Journal Panel'
Assert-True (($wideNext.X + $wideNext.Width) -le $widePanelSeparator.X) 'wide Next stays inside the Journal Panel'
$wideWheel = @(
    foreach ($line in $executionWide.Lines) {
        $line.Segments | Where-Object { $_.Text -eq 'Wheel' }
    }
)
Assert-Equal 1 $wideWheel.Count 'wide Execution exposes one scrolling command indication'
Assert-True (($wideWheel[0].X + $wideWheel[0].Text.Length) -lt $widePanelSeparator.X) 'wide scrolling indication belongs to the Journal Panel'
$executionPagingSeparator = Get-RoleLineIndex -Frame $executionWide -PresentationRole PagingSeparator
Assert-Equal ($executionPagingSeparator + 1) $widePrevious.Y 'wide Journal content is separated from its paging controls'

$executionNarrow = Get-TerminalInteractionFrame -View $execution -OwnerActionMenu $root -Width 60 -Height 20 -FocusedTargetId navigation.back -JournalOffset ([int]::MaxValue)
$executionNarrowText = @(ConvertTo-TerminalFrameText -Frame $executionNarrow)
$journalTitleIndex = [Array]::IndexOf($executionNarrowText, '  Execution Journal')
$trackingTitleIndex = [Array]::IndexOf($executionNarrowText, '  Execution Tracking')
Assert-True ($journalTitleIndex -ge 0 -and $trackingTitleIndex -gt $journalTitleIndex) 'narrow Execution preserves Journal then Tracking order'
Assert-True (($executionNarrowText -join "`n") -match 'Result: Preview only') 'narrow Execution keeps the final Result visible'
Assert-Equal 1 (Get-RoleLineIndex -Frame $executionNarrow -PresentationRole PrimarySeparator) 'Execution keeps the stable Header height'
Assert-True (@(
    foreach ($line in $executionNarrow.Lines) {
        $line.Segments | Where-Object { $_.PresentationRole -eq 'PanelSeparator' }
    }
).Count -eq 1) 'narrow Panel framing owns one separator between Journal and Tracking'
foreach ($line in @(ConvertTo-TerminalFrameText -Frame $executionNarrow -PreserveWidth)) {
    Assert-Equal 60 $line.Length 'Execution clipping protects narrow width'
}

# Variant cells keep a width floor: past it the grid drops a column and the
# row wraps beneath its first cell, never beneath the label, without a gap.
$bumpVariants = @(foreach ($value in @('patch', 'minor', 'major')) {
    New-TerminalTarget -TargetId "action.bump.$value" -Label $value -IntentKind Action -Payload ([pscustomobject]@{ Variant = $value })
})
$bumpAccesses = @(foreach ($name in @('release', 'maintenance', 'setup')) {
    New-TerminalTarget -TargetId "access.$name" -Label "$name…" -IntentKind Access -Payload ([pscustomobject]@{ AccessId = $name }) -PresentationRole Access
})
$bumpMenu = New-TerminalActionMenuView -ViewId menu.bump -Banner 'Bump' -Sections @(
    New-TerminalSection -Label Project -Items @(New-TerminalActionRow -Label 'Record version' -Variants $bumpVariants)
    New-TerminalSection -Label $null -Items $bumpAccesses
)
$bumpRoomy = Get-TerminalInteractionFrame -View $bumpMenu -Width 100 -Height 12 -FocusedTargetId action.bump.patch
$roomyPatch = Get-Placement -Frame $bumpRoomy -TargetId action.bump.patch
$roomyMajor = Get-Placement -Frame $bumpRoomy -TargetId action.bump.major
Assert-Equal $roomyPatch.Y $roomyMajor.Y 'three Variants share one line while their cells stay above the floor'
Assert-True ($roomyPatch.Width -ge 22) 'a roomy terminal keeps Variant cells above the width floor'
$roomyRelease = Get-Placement -Frame $bumpRoomy -TargetId access.release
$roomySetup = Get-Placement -Frame $bumpRoomy -TargetId access.setup
Assert-Equal $roomyRelease.Y $roomySetup.Y 'three Accesses fill the three Variant columns of their level on one line'
Assert-Equal $roomyMajor.X $roomySetup.X 'Accesses align on the Variant columns'
$bumpTight = Get-TerminalInteractionFrame -View $bumpMenu -Width 72 -Height 12 -FocusedTargetId action.bump.patch
$tightPatch = Get-Placement -Frame $bumpTight -TargetId action.bump.patch
$tightMinor = Get-Placement -Frame $bumpTight -TargetId action.bump.minor
$tightMajor = Get-Placement -Frame $bumpTight -TargetId action.bump.major
Assert-True ($tightPatch.Width -ge 22) 'a tight terminal drops a column before a cell shrinks below the floor'
Assert-Equal $tightPatch.Y $tightMinor.Y 'the first two Variants keep the label line'
Assert-Equal ($tightPatch.Y + 1) $tightMajor.Y 'the third Variant wraps to the very next line'
Assert-Equal $tightPatch.X $tightMajor.X 'a wrapped Variant sits beneath the first cell, not beneath the label'
$labelLine = @($bumpTight.Lines | ForEach-Object { $_.Segments } | Where-Object { $_.PresentationRole -eq 'ActionLabel' })
Assert-Equal 1 $labelLine.Count 'the label is written once, on the first line of its row'

# A frame line paints as runs that cover every cell exactly once and
# reproduce its text, so the Host writes it in one pass without a blank first.
$module = Get-Module terminal-interaction
$paintWidth = $wide.Width - 1
$bannerRuns = 0
foreach ($line in $wide.Lines) {
    $runs = @(& $module { param($line, $paintWidth) ConvertTo-TerminalFrameRuns -Line $line -PaintWidth $paintWidth } $line $paintWidth)
    $expected = (-join (& $module { param($line) ConvertTo-TerminalFrameCharacters -Line $line } $line)).Substring(0, $paintWidth)
    Assert-Equal $expected (-join ($runs | ForEach-Object Text)) 'runs reproduce the line text'
    $cursor = 0
    foreach ($run in $runs) {
        Assert-Equal $cursor $run.X 'runs are contiguous'
        $cursor += $run.Text.Length
        if ($null -ne $run.Segment -and $run.Segment.PresentationRole -eq 'Banner') { $bannerRuns++ }
    }
    Assert-Equal $paintWidth $cursor 'runs cover the painted width exactly once'
}
Assert-Equal 1 $bannerRuns 'the banner paints as one run carrying its segment role'

# Under an Action Row, the independent Actions of the Section fill the grid
# columns after one blank line: they are Actions of their own, not more
# Variants of the row above, and the gap says so without a heading.
$versionActions = @(
    New-TerminalTarget -TargetId action.preview-changelog -Label 'Preview changelog' -IntentKind Action -Payload ([pscustomobject]@{ ActionId = 'preview-changelog' })
    New-TerminalTarget -TargetId action.write-changelog -Label 'Write changelog' -IntentKind Action -Payload ([pscustomobject]@{ ActionId = 'write-changelog' })
    New-TerminalTarget -TargetId action.mark-release -Label 'Mark release' -IntentKind Action -Payload ([pscustomobject]@{ ActionId = 'mark-release' })
)
$quitTarget = New-TerminalTarget -TargetId command.quit -Label Quit -IntentKind Command -Payload ([pscustomobject]@{ Command = 'Exit' }) -PresentationRole Exit
$versionsMenu = New-TerminalActionMenuView -ViewId menu.versions -Banner 'Versions' -Sections @(
    New-TerminalSection -Label $null -Items (@(New-TerminalActionRow -Label 'Record version' -Variants $bumpVariants) + $versionActions + @($quitTarget))
)
$versionsFrame = Get-TerminalInteractionFrame -View $versionsMenu -Width 100 -Height 24 -FocusedTargetId action.bump.patch
$versionsPatch = Get-Placement -Frame $versionsFrame -TargetId action.bump.patch
$versionsMajor = Get-Placement -Frame $versionsFrame -TargetId action.bump.major
$previewChangelog = Get-Placement -Frame $versionsFrame -TargetId action.preview-changelog
$writeChangelog = Get-Placement -Frame $versionsFrame -TargetId action.write-changelog
$markRelease = Get-Placement -Frame $versionsFrame -TargetId action.mark-release
$versionsQuit = Get-Placement -Frame $versionsFrame -TargetId command.quit
Assert-Equal ($versionsMajor.Y + 2) $previewChangelog.Y 'one blank line parts the independent Actions from the Action Row'
Assert-Equal 0 $versionsFrame.Lines[$versionsMajor.Y + 1].Segments.Count 'the parting line is empty'
Assert-Equal $versionsPatch.X $previewChangelog.X 'the first independent Action takes the first grid column'
Assert-Equal $previewChangelog.Y $writeChangelog.Y 'independent Actions fill the grid columns'
Assert-Equal (Get-Placement -Frame $versionsFrame -TargetId action.bump.minor).X $writeChangelog.X 'independent Actions sit on the Variant columns'
Assert-Equal (3 + 'Record version'.Length + 3) $versionsPatch.X 'independent Actions leave the label column to the Action Row'
Assert-Equal $markRelease.Y $versionsQuit.Y 'Quit seats on the last line, beside the last independent Action'
Assert-Equal 98 ($versionsQuit.X + $versionsQuit.Width) 'Quit keeps the right rail beside an independent Action'
$versionsWrapped = Get-TerminalInteractionFrame -View $versionsMenu -Width 80 -Height 24 -FocusedTargetId action.bump.patch
$wrappedMajor = Get-Placement -Frame $versionsWrapped -TargetId action.bump.major
$wrappedPreview = Get-Placement -Frame $versionsWrapped -TargetId action.preview-changelog
$wrappedMark = Get-Placement -Frame $versionsWrapped -TargetId action.mark-release
Assert-Equal ($wrappedMajor.Y + 2) $wrappedPreview.Y 'the blank line follows the last wrapped Variant line'
Assert-Equal ($wrappedPreview.Y + 1) $wrappedMark.Y 'independent Actions wrap like Variants, with no further gap'
Assert-Equal $wrappedPreview.X $wrappedMark.X 'a wrapped independent Action starts under the first column'
$versionsNarrow = Get-TerminalInteractionFrame -View $versionsMenu -Width 60 -Height 30 -FocusedTargetId action.bump.patch
$narrowMajor = Get-Placement -Frame $versionsNarrow -TargetId action.bump.major
$narrowPreview = Get-Placement -Frame $versionsNarrow -TargetId action.preview-changelog
Assert-Equal ($narrowMajor.Y + 2) $narrowPreview.Y 'a narrow terminal keeps the blank line under the last Variant'
Assert-Equal $narrowMajor.X $narrowPreview.X 'a narrow terminal lists independent Actions on the Variant track'
$maintenanceLike = New-TerminalActionMenuView -ViewId menu.plain -Banner 'Plain' -Sections @(
    New-TerminalSection -Label $null -Items ($versionActions + @($quitTarget))
)
$plainFrame = Get-TerminalInteractionFrame -View $maintenanceLike -Width 100 -Height 24 -FocusedTargetId action.preview-changelog

# In a nested menu, an untitled Action Row then labelled Sections carry no
# heading between them: each row sits on the very next line.
$gitLike = New-TerminalActionMenuView -ViewId menu.git -Banner 'Deckle' -Context 'Git and versions' -BackTarget $project.BackTarget -Sections @(
    New-TerminalSection -Label $null -Items @(New-TerminalActionRow -Label 'Record version' -Variants $bumpVariants)
    New-TerminalSection -Label Release -Items @($versionActions[2])
    New-TerminalSection -Label Changelog -Items @($versionActions[0], $versionActions[1])
)
$gitFrame = Get-TerminalInteractionFrame -View $gitLike -Width 120 -Height 24 -FocusedTargetId action.bump.patch
$gitPatch = Get-Placement -Frame $gitFrame -TargetId action.bump.patch
$gitMark = Get-Placement -Frame $gitFrame -TargetId action.mark-release
$gitPreview = Get-Placement -Frame $gitFrame -TargetId action.preview-changelog
Assert-Equal ($gitPatch.Y + 1) $gitMark.Y 'a nested Section follows an untitled Action Row on the next line'
Assert-Equal ($gitMark.Y + 1) $gitPreview.Y 'nested Sections follow one another on the next line'
Assert-Equal ((Get-RoleLineIndex -Frame $plainFrame -PresentationRole PrimarySeparator) + 2) (Get-Placement -Frame $plainFrame -TargetId action.preview-changelog).Y 'without an Action Row above, independent Actions open the body with no gap'

# A logo opens the Header when the terminal affords it: Unicode output, a
# width that holds it, and twelve body lines left under the Header.
$logo = @('XX XX', 'XX XX  SCRIPTS')
$logoFrame = Get-TerminalInteractionFrame -View $root -Width 100 -Height 24 -FocusedTargetId action.launch.release -Logo $logo
Assert-Equal 4 (Get-RoleLineIndex -Frame $logoFrame -PresentationRole PrimarySeparator) 'the logo and its gap lift the Header by three lines'
Assert-Equal 'Banner' $logoFrame.Lines[0].Segments[0].PresentationRole 'the logo takes the Banner role'
Assert-Equal 'XX XX  SCRIPTS' $logoFrame.Lines[1].Segments[0].Text 'the logo lines open the frame in order'
Assert-Equal 0 $logoFrame.Lines[2].Segments.Count 'one blank line separates the logo from the title line'
Assert-Equal ($launchRelease.Y + 3) (Get-Placement -Frame $logoFrame -TargetId action.launch.release).Y 'the body follows the logo'
Assert-Equal 4 (Get-RoleLineIndex -Frame (Get-TerminalInteractionFrame -View $root -Width 100 -Height 17 -Logo $logo) -PresentationRole PrimarySeparator) 'seventeen lines still afford the logo'
Assert-Equal 1 (Get-RoleLineIndex -Frame (Get-TerminalInteractionFrame -View $root -Width 100 -Height 16 -Logo $logo) -PresentationRole PrimarySeparator) 'a shorter terminal drops the logo before the body'
Assert-Equal 1 (Get-RoleLineIndex -Frame (Get-TerminalInteractionFrame -View $root -Width 100 -Height 24 -Logo $logo -SupportsUnicode $false) -PresentationRole PrimarySeparator) 'an ASCII-only host draws no logo'
Assert-Equal 1 (Get-RoleLineIndex -Frame (Get-TerminalInteractionFrame -View $root -Width 20 -Height 24 -Logo @('X' * 30)) -PresentationRole PrimarySeparator) 'a terminal narrower than the logo draws none'

Write-Host 'layout.tests.ps1: PASS' -ForegroundColor Green
