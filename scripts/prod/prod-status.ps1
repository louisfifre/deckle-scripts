<#
.SYNOPSIS
    Prod of every project
.DESCRIPTION
    Walks the repositories beside this one and, for each that has prod
    settings, reports the version running, the version staged for the next
    start and how far the running build is behind origin. Changes nothing but
    the remote-tracking refs a fetch moves.
.NOTES
    order: 110
    action: Prod of every project |
#>

[CmdletBinding()]
param(
    # Folders whose child folders are the repositories to walk. By default the
    # folder that holds this repository's primary checkout (C:\Code\projects for
    # C:\Code\projects\deckle).
    [string[]]$Path,
    # Read origin as last fetched instead of fetching it.
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'
$LibDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
. (Join-Path $LibDir 'action-summary.ps1')
. (Join-Path $PSScriptRoot 'prod-common.ps1')

$Workflow = 'Prod of every project'

trap {
    Write-ActionSummary -Workflow $Workflow -Result Failed -Sentence 'The prod status of the projects could not be read.' `
        -Details ([ordered]@{ Error = $_.Exception.Message })
    throw
}

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @(Split-Path -Parent (Get-ProdPrimaryCheckout -From $PSScriptRoot))
}
$output = New-WorkflowOutput -Category 'prod'

$repositories = foreach ($folder in $Path) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "Folder not found: $folder" }
    # A primary checkout has a .git folder; a linked worktree only a .git file,
    # and it shares its primary's prod copy, so it is not walked twice.
    Get-ChildItem -LiteralPath $folder -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') -PathType Container }
}
$repositories = @($repositories | Sort-Object Name)

$states = [System.Collections.Generic.List[object]]::new()
$without = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
foreach ($repository in $repositories) {
    if (-not (Test-Path -LiteralPath (Get-ProdSettingsPath -Primary $repository.FullName) -PathType Leaf)) {
        $without.Add($repository.Name)
        continue
    }
    try {
        $state = Get-ProdState -Primary $repository.FullName -NoFetch:$NoFetch
        $states.Add($state)
        $lagRole = if ($state.Behind -eq 0) { 'Success' } elseif ($null -eq $state.Behind) { 'Muted' } else { 'Warning' }
        Write-WorkflowStep -Output $output -Message $state.Repository
        Write-WorkflowMessage -Output $output -Message "running  $($state.Running)"
        Write-WorkflowMessage -Output $output -Message "staged   $($state.Staged)" -Role $(if ($state.StagedStamp) { 'Action' } else { 'Muted' })
        Write-WorkflowMessage -Output $output -Message "origin   $($state.Latest), $(Format-ProdBehind $state)" -Role $lagRole
        if ($state.OriginError) { Write-WorkflowMessage -Output $output -Message $state.OriginError -Role Warning }
    } catch {
        $failures.Add("$($repository.Name): $($_.Exception.Message)")
        Write-WorkflowStep -Output $output -Message $repository.Name
        Write-WorkflowMessage -Output $output -Message $_.Exception.Message -Role Error
    }
}

$behind = @($states | Where-Object { $_.Behind -gt 0 })
$waiting = @($states | Where-Object { $_.StagedStamp })
$result = if ($failures.Count -gt 0) { 'Partial' } else { 'Success' }
$sentence = if ($states.Count -eq 0 -and $failures.Count -eq 0) {
    'No repository here has prod settings.'
} else {
    "$($states.Count) project(s) with a prod copy: $($behind.Count) behind origin, $($waiting.Count) with a build waiting for the next start."
}
Write-ActionSummary -Workflow $Workflow -Result $result -Sentence $sentence `
    -Details ([ordered]@{
        Walked    = $Path -join ', '
        Behind    = @($behind | ForEach-Object Repository)
        Waiting   = @($waiting | ForEach-Object Repository)
        'No prod' = @($without)
        Failed    = @($failures)
    })

if ($result -eq 'Partial') { exit 1 }
