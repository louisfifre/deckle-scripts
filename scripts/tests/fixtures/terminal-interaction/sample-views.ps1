# Sample Views for the terminal-interaction tests: a fixed catalog that
# exercises every View kind (Action Rows, nested Sections, Accesses, a
# Preparation and an Execution) without any repository behind it. The names
# echo a real launcher so the frames read naturally in the assertions.

function New-SampleBackTarget {
    return New-TerminalTarget `
        -TargetId 'navigation.back' `
        -Label '< Back' `
        -IntentKind Navigation `
        -Payload ([pscustomobject]@{ Command = 'Back' }) `
        -PresentationRole Navigation
}

function New-SampleActionTarget {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Label,
        [string]$Variant,
        [ValidateSet('Action', 'Danger')][string]$Role = 'Action'
    )

    $targetId = if ($Variant) { "action.$ActionId.$($Variant.ToLowerInvariant())" } else { "action.$ActionId" }
    return New-TerminalTarget `
        -TargetId $targetId `
        -Label $Label `
        -IntentKind Action `
        -Payload ([pscustomobject]@{ ActionId = $ActionId; Variant = $Variant; Label = $Label }) `
        -PresentationRole $Role
}

function New-SampleAccessTarget {
    param(
        [Parameter(Mandatory)][string]$AccessId,
        [Parameter(Mandatory)][string]$Label
    )

    return New-TerminalTarget `
        -TargetId "access.$AccessId" `
        -Label ($Label + [char]0x2026) `
        -IntentKind Access `
        -Payload ([pscustomobject]@{ AccessId = $AccessId })
}

function Get-SampleRootView {
    $release = New-SampleActionTarget -ActionId launch -Label Release -Variant Release
    $debug = New-SampleActionTarget -ActionId launch -Label Debug -Variant Debug
    $buildRunRelease = New-SampleActionTarget -ActionId build-run -Label Release -Variant Release
    $buildRunDebug = New-SampleActionTarget -ActionId build-run -Label Debug -Variant Debug
    $buildRelease = New-SampleActionTarget -ActionId build -Label Release -Variant Release
    $buildDebug = New-SampleActionTarget -ActionId build -Label Debug -Variant Debug

    $project = New-SampleAccessTarget -AccessId project -Label Project
    $releaseAccess = New-SampleAccessTarget -AccessId release -Label Release
    $maintenance = New-SampleAccessTarget -AccessId maintenance -Label Maintenance
    $setup = New-SampleAccessTarget -AccessId setup -Label Setup
    $quit = New-TerminalTarget `
        -TargetId command.quit `
        -Label Quit `
        -IntentKind Command `
        -Payload ([pscustomobject]@{ Command = 'Exit' }) `
        -PresentationRole Exit

    $sections = @(
        New-TerminalSection -Label Run -Items @(
            New-TerminalActionRow -Label Launch -Variants @($release, $debug)
            New-TerminalActionRow -Label 'Build & run' -Variants @($buildRunRelease, $buildRunDebug)
            New-TerminalActionRow -Label 'Build (no run)' -Variants @($buildRelease, $buildDebug)
        )
        New-TerminalSection -Label Workspace -Items @($project, $releaseAccess, $maintenance, $setup, $quit)
    )
    return New-TerminalActionMenuView -ViewId menu.root -Banner 'Deckle Scripts' -Sections $sections
}

function Get-SampleProjectView {
    return New-TerminalActionMenuView `
        -ViewId menu.project `
        -Banner 'Deckle Scripts' `
        -Context Project `
        -BackTarget (New-SampleBackTarget) `
        -Sections @(
            New-TerminalSection -Label Docs -Items @(
                New-SampleActionTarget -ActionId readme-stats -Label 'README pulse'
                New-SampleActionTarget -ActionId changelog -Label Changelog
            )
            New-TerminalSection -Label Version -Items @(
                New-SampleActionTarget -ActionId record-version -Label 'Record version'
            )
        )
}

function Get-SampleReleaseView {
    return New-TerminalActionMenuView `
        -ViewId menu.release `
        -Banner 'Deckle Scripts' `
        -Context Release `
        -BackTarget (New-SampleBackTarget) `
        -Sections @(
            New-TerminalSection -Label Publish -Items @(
                New-SampleActionTarget -ActionId publish-app -Label App
                New-SampleActionTarget -ActionId publish-native -Label 'Native runtime'
            )
            New-TerminalSection -Label Prepare -Items @(
                New-SampleActionTarget -ActionId prepare-app -Label 'App artifacts'
                New-SampleActionTarget -ActionId prepare-native -Label 'Native runtime'
            )
        )
}

function Get-SampleMaintenanceView {
    return New-TerminalActionMenuView `
        -ViewId menu.maintenance `
        -Banner 'Deckle Scripts' `
        -Context Maintenance `
        -BackTarget (New-SampleBackTarget) `
        -Sections @(
            New-TerminalSection -Label Statistics -Items @(
                New-SampleActionTarget -ActionId repository-stats -Label 'Repository statistics'
                New-SampleActionTarget -ActionId context-stats -Label 'Context statistics'
            )
            New-TerminalSection -Label Cleanup -Items @(
                New-SampleActionTarget -ActionId clean -Label 'Clean build outputs'
                New-SampleActionTarget -ActionId build-servers -Label 'Stop .NET build servers'
            )
            New-TerminalSection -Label 'AI sessions' -Items @(
                New-SampleActionTarget -ActionId inspect-agent-state -Label 'Inspect AI session state'
                New-SampleActionTarget -ActionId reset-agent-state -Label 'Reset AI session state' -Role Danger
            )
        )
}

function Get-SampleSetupView {
    return New-TerminalActionMenuView `
        -ViewId menu.setup `
        -Banner 'Deckle Scripts' `
        -Context Setup `
        -BackTarget (New-SampleBackTarget) `
        -Sections @(
            New-TerminalSection -Label Machine -Items @(
                New-SampleActionTarget -ActionId bootstrap -Label Bootstrap
                New-SampleActionTarget -ActionId assets -Label 'Runtime assets'
            )
            New-TerminalSection -Label Repo -Items @(
                New-SampleActionTarget -ActionId hooks -Label 'Install git hooks'
            )
        )
}

function Get-SampleAccessView {
    param([Parameter(Mandatory)][string]$AccessId)

    switch ($AccessId) {
        'project' { return Get-SampleProjectView }
        'release' { return Get-SampleReleaseView }
        'maintenance' { return Get-SampleMaintenanceView }
        'setup' { return Get-SampleSetupView }
        default { throw "Unknown sample Access '$AccessId'." }
    }
}

function Get-SamplePreparationView {
    # A Preparation with the four Selector shapes: a Multiple one with a
    # scope, a Single one, a Multiple one and a Single one again.
    $revision = 1
    $scopeOptions = @(
        New-TerminalSelectionOption -OptionId root-files -Label 'Root files' -Value root-files
        New-TerminalSelectionOption -OptionId 'folder:docs' -Label 'docs/' -Value docs
        New-TerminalSelectionOption -OptionId 'folder:src' -Label 'src/' -Value src
    )
    $fileOptions = @(
        New-TerminalSelectionOption -OptionId all -Label 'All tracked files' -Value all
        New-TerminalSelectionOption -OptionId text -Label 'Supported text' -Value text
        New-TerminalSelectionOption -OptionId source -Label 'C#, XAML, RESW' -Value source
        New-TerminalSelectionOption -OptionId docs -Label 'Documentation' -Value documentation
    )
    $measureOptions = @(
        New-TerminalSelectionOption -OptionId files -Label 'File count' -Value files
        New-TerminalSelectionOption -OptionId bytes -Label 'Size' -Value bytes
        New-TerminalSelectionOption -OptionId lines -Label 'Text lines' -Value lines
        New-TerminalSelectionOption -OptionId source -Label 'Source LOC' -Value source
    )
    $groupingOptions = @(
        New-TerminalSelectionOption -OptionId extension -Label 'File extension' -Value extension
        New-TerminalSelectionOption -OptionId folder -Label 'Top-level folder' -Value folder
        New-TerminalSelectionOption -OptionId none -Label 'No grouping' -Value none
    )
    $selectors = @(
        New-TerminalSelector -SelectorId scope -FilterLabel Scope -SelectionMode Multiple -Options $scopeOptions -SelectedValues @('root-files', 'docs', 'src')
        New-TerminalSelector -SelectorId files -FilterLabel Files -SelectionMode Single -Options $fileOptions -SelectedValues @('all')
        New-TerminalSelector -SelectorId measures -FilterLabel Measures -SelectionMode Multiple -Options $measureOptions -SelectedValues @('files', 'bytes')
        New-TerminalSelector -SelectorId grouping -FilterLabel Grouping -SelectionMode Single -Options $groupingOptions -SelectedValues @('extension')
    )
    $effectiveScope = New-TerminalEffectiveScope `
        -Revision $revision `
        -State Resolved `
        -Lines @(
            'Whole repository.'
            'All tracked files; tracked files only.'
            'Links and junctions are excluded.'
        )
    $review = New-TerminalReview `
        -Revision $revision `
        -Lines @(
            'Action: Repository statistics'
            'Scope: Whole repository'
            'Files: All tracked files'
            'Measures: File count, Size'
            'Grouping: File extension'
        )
    $confirmation = New-TerminalTarget `
        -TargetId confirmation.repository-stats.run `
        -Label 'Run scan' `
        -IntentKind Action `
        -Payload ([pscustomobject][ordered]@{
            ActionId = 'repository-stats'
            Variant = $null
            Label = 'Repository statistics'
            PreparationRevision = $revision
        }) `
        -PresentationRole Action
    return New-TerminalPreparationView `
        -ViewId preparation.repository-stats `
        -Banner 'Deckle Scripts' `
        -Context 'Maintenance / Repository statistics' `
        -ActionId repository-stats `
        -Revision $revision `
        -Selectors $selectors `
        -EffectiveScope $effectiveScope `
        -Review $review `
        -ConfirmationTarget $confirmation `
        -BackTarget (New-SampleBackTarget) `
        -OwnerActionMenuId menu.maintenance
}

function Get-SampleExecutionView {
    # A completed run with a Journal long enough to page and one line long
    # enough to clip.
    $journal = [System.Collections.Generic.List[object]]::new()
    $journal.Add('[preview] No repository command was started.')
    $journal.Add('[intent] Action build / Release')
    $journal.Add('[core] Intent Request accepted by the sample handler.')
    $journal.Add('[runtime] Installed an in-memory Execution View.')
    $journal.Add('')
    for ($index = 1; $index -le 28; $index++) {
        $journal.Add(('[sample] Journal line {0:d2} keeps its complete logical value for clipping and paging validation.' -f $index))
    }
    $journal.Add('[sample] This deliberately long line should be clipped at the Journal Panel boundary without wrapping into the Tracking Panel or changing the stored value.')
    $journal.Add('[preview] Completed safely.')

    $tracking = @(
        [pscustomobject]@{ Label = 'Accept intent'; State = 'Completed' }
        [pscustomobject]@{ Label = 'Freeze request'; State = 'Completed' }
        [pscustomobject]@{ Label = 'Render sample'; State = 'Completed' }
    )
    return New-TerminalExecutionView `
        -ViewId 'execution.build' `
        -Banner 'Deckle Scripts' `
        -Context 'Build / Release' `
        -State Completed `
        -JournalLines @($journal) `
        -TrackingSteps $tracking `
        -Result 'Preview only; no repository changes.' `
        -BackTarget (New-SampleBackTarget) `
        -OwnerActionMenuId menu.root
}

function Get-SampleSnapshotView {
    param([Parameter(Mandatory)][ValidateSet('Menu', 'Project', 'Preparation', 'Execution')][string]$Name)

    switch ($Name) {
        'Menu' { return Get-SampleRootView }
        'Project' { return Get-SampleProjectView }
        'Preparation' { return Get-SamplePreparationView }
        'Execution' { return Get-SampleExecutionView }
    }
}
