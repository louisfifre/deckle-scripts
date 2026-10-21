# Deckle-specific descriptors for the parallel interaction preview.

function New-LauncherBackTarget {
    return New-TerminalTarget `
        -TargetId 'navigation.back' `
        -Label '< Back' `
        -IntentKind Navigation `
        -Payload ([pscustomobject]@{ Command = 'Back' }) `
        -PresentationRole Navigation
}

function New-LauncherActionTarget {
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

function New-LauncherAccessTarget {
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

function Get-LauncherRootView {
    $release = New-LauncherActionTarget -ActionId launch -Label Release -Variant Release
    $debug = New-LauncherActionTarget -ActionId launch -Label Debug -Variant Debug
    $buildRunRelease = New-LauncherActionTarget -ActionId build-run -Label Release -Variant Release
    $buildRunDebug = New-LauncherActionTarget -ActionId build-run -Label Debug -Variant Debug
    $buildRelease = New-LauncherActionTarget -ActionId build -Label Release -Variant Release
    $buildDebug = New-LauncherActionTarget -ActionId build -Label Debug -Variant Debug

    $project = New-LauncherAccessTarget -AccessId project -Label Project
    $releaseAccess = New-LauncherAccessTarget -AccessId release -Label Release
    $maintenance = New-LauncherAccessTarget -AccessId maintenance -Label Maintenance
    $setup = New-LauncherAccessTarget -AccessId setup -Label Setup
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

function Get-LauncherProjectView {
    return New-TerminalActionMenuView `
        -ViewId menu.project `
        -Banner 'Deckle Scripts' `
        -Context Project `
        -BackTarget (New-LauncherBackTarget) `
        -Sections @(
            New-TerminalSection -Label Docs -Items @(
                New-LauncherActionTarget -ActionId readme-stats -Label 'README pulse'
                New-LauncherActionTarget -ActionId changelog -Label Changelog
            )
            New-TerminalSection -Label Version -Items @(
                New-LauncherActionTarget -ActionId record-version -Label 'Record version'
            )
        )
}

function Get-LauncherReleaseView {
    return New-TerminalActionMenuView `
        -ViewId menu.release `
        -Banner 'Deckle Scripts' `
        -Context Release `
        -BackTarget (New-LauncherBackTarget) `
        -Sections @(
            New-TerminalSection -Label Publish -Items @(
                New-LauncherActionTarget -ActionId publish-app -Label App
                New-LauncherActionTarget -ActionId publish-native -Label 'Native runtime'
            )
            New-TerminalSection -Label Prepare -Items @(
                New-LauncherActionTarget -ActionId prepare-app -Label 'App artifacts'
                New-LauncherActionTarget -ActionId prepare-native -Label 'Native runtime'
            )
        )
}

function Get-LauncherMaintenanceView {
    return New-TerminalActionMenuView `
        -ViewId menu.maintenance `
        -Banner 'Deckle Scripts' `
        -Context Maintenance `
        -BackTarget (New-LauncherBackTarget) `
        -Sections @(
            New-TerminalSection -Label Statistics -Items @(
                New-LauncherActionTarget -ActionId repository-stats -Label 'Repository statistics'
                New-LauncherActionTarget -ActionId context-stats -Label 'Context statistics'
            )
            New-TerminalSection -Label Cleanup -Items @(
                New-LauncherActionTarget -ActionId clean -Label 'Clean build outputs'
                New-LauncherActionTarget -ActionId build-servers -Label 'Stop .NET build servers'
            )
            New-TerminalSection -Label 'AI sessions' -Items @(
                New-LauncherActionTarget -ActionId inspect-agent-state -Label 'Inspect AI session state'
                New-LauncherActionTarget -ActionId reset-agent-state -Label 'Reset AI session state' -Role Danger
            )
        )
}

function Get-LauncherSetupView {
    return New-TerminalActionMenuView `
        -ViewId menu.setup `
        -Banner 'Deckle Scripts' `
        -Context Setup `
        -BackTarget (New-LauncherBackTarget) `
        -Sections @(
            New-TerminalSection -Label Machine -Items @(
                New-LauncherActionTarget -ActionId bootstrap -Label Bootstrap
                New-LauncherActionTarget -ActionId assets -Label 'Runtime assets'
            )
            New-TerminalSection -Label Repo -Items @(
                New-LauncherActionTarget -ActionId hooks -Label 'Install git hooks'
            )
        )
}

function Get-LauncherAccessView {
    param([Parameter(Mandatory)][string]$AccessId)

    switch ($AccessId) {
        'project' { return Get-LauncherProjectView }
        'release' { return Get-LauncherReleaseView }
        'maintenance' { return Get-LauncherMaintenanceView }
        'setup' { return Get-LauncherSetupView }
        default { throw "Unknown preview Access '$AccessId'." }
    }
}
