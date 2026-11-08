$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
Import-Module (Join-Path $LibDir 'agent-state-maintenance.psm1') -Force

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw ($Case + ": expected $Expected, got $Actual") }
}

function Assert-True([bool]$Value, [string]$Case) {
    if (-not $Value) { throw ($Case + ': expected true') }
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Case) {
    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw ($Case + ": unexpected error: $($_.Exception.Message)")
        }
        return
    }
    throw ($Case + ': expected an error')
}

$claudeProfile = [ordered]@{
    oauthAccount = [ordered]@{ accountUuid = 'account-1' }
    mcpServers = [ordered]@{ figma = [ordered]@{ type = 'http' } }
    projects = [ordered]@{ 'D:\old-project' = [ordered]@{ trust = $true } }
}
$claudeClean = ConvertTo-CleanClaudeProfile -Json ($claudeProfile | ConvertTo-Json -Depth 20) | ConvertFrom-Json -Depth 20
Assert-Equal 0 @($claudeClean.projects.PSObject.Properties).Count 'Claude projects are cleared'
Assert-Equal 'account-1' $claudeClean.oauthAccount.accountUuid 'Claude account is preserved'
Assert-Equal 'http' $claudeClean.mcpServers.figma.type 'Claude global MCP is preserved'

$desktopConfig = [ordered]@{
    globalShortcut = 'Ctrl+Alt+Space'
    mcpServers = [ordered]@{ figma = [ordered]@{ command = 'keep' } }
    preferences = [ordered]@{
        launchPreviewPersistedWorkspaces = @('D:\old-project')
        launchPreviewSessionScopedSessions = @('session-1')
        'chillingSlothLocation.customPath' = 'D:\worktrees\sample'
        epitaxyPrefs = [ordered]@{
            'epitaxy-folder-permission-mode.account-1' = [ordered]@{ 'D:\old-project' = 'allow' }
            'epitaxy-perm-mode-acks.account-1' = @('D:\old-project')
            'starred-local-code-sessions' = @('session-1')
            'starred-session-groups' = @('group-1')
            'starred-cowork-spaces' = @('space-1')
            'dframe-local-slice' = [ordered]@{
                homeProjectsPinnedOrder = @('D:\old-project')
                pinnedOrder = @('D:\old-project')
            }
            'ccd-sessions-filter' = [ordered]@{
                state = [ordered]@{ selectedProjects = @('D:\old-project') }
            }
            'cc-landing-worktree-enabled' = $true
            theme = 'dark'
        }
    }
}
$desktopClean = ConvertTo-CleanClaudeDesktopConfig -Json ($desktopConfig | ConvertTo-Json -Depth 20) | ConvertFrom-Json -Depth 20
Assert-Equal 0 @($desktopClean.preferences.epitaxyPrefs.'epitaxy-folder-permission-mode.account-1'.PSObject.Properties).Count 'Claude folder permissions are cleared'
Assert-Equal 0 @($desktopClean.preferences.epitaxyPrefs.'epitaxy-perm-mode-acks.account-1').Count 'Claude folder acknowledgements are cleared'
Assert-Equal 0 @($desktopClean.preferences.epitaxyPrefs.'ccd-sessions-filter'.state.selectedProjects).Count 'Claude selected projects are cleared'
Assert-Equal 0 @($desktopClean.preferences.epitaxyPrefs.'dframe-local-slice'.pinnedOrder).Count 'Claude project pins are cleared'
Assert-Equal 0 @($desktopClean.preferences.'launchPreviewPersistedWorkspaces').Count 'Claude launch workspaces are cleared'
Assert-Equal 'D:\worktrees\sample' $desktopClean.preferences.'chillingSlothLocation.customPath' 'Claude worktree location is preserved'
Assert-Equal $true $desktopClean.preferences.epitaxyPrefs.'cc-landing-worktree-enabled' 'Claude worktree preference is preserved'
Assert-Equal 'dark' $desktopClean.preferences.epitaxyPrefs.theme 'Claude unrelated UI preference is preserved'
Assert-Equal 'Ctrl+Alt+Space' $desktopClean.globalShortcut 'Claude Desktop shortcut is preserved'
Assert-Equal 'keep' $desktopClean.mcpServers.figma.command 'Claude Desktop MCP configuration is preserved'

Assert-Throws { Assert-AgentStatePath -Path 'D:\outside' -Root 'C:\safe' } 'escapes' 'Path boundary is enforced'
Assert-Throws { Assert-AgentProcessesStopped -ProcessNames @('explorer', 'ChatGPT') } 'ChatGPT' 'Active ChatGPT blocks reset'
Assert-AgentProcessesStopped -ProcessNames @('explorer')

$broadRoot = Join-Path ([IO.Path]::GetTempPath()) "agent-state-broad-$([guid]::NewGuid())"
try {
    $null = New-Item -ItemType Directory -Path $broadRoot -Force
    Set-Content -LiteralPath (Join-Path $broadRoot '.credentials.json') -Value '{"oauth":"keep"}' -Encoding utf8NoBOM
    Assert-Throws {
        Get-AgentStateCleanupPlan -Scope Claude -UserProfileRoot $broadRoot -ClaudeHome $broadRoot
    } 'broad Claude state root' 'The whole user profile cannot become a cleanup root'
} finally {
    if (Test-Path -LiteralPath $broadRoot) { Remove-Item -LiteralPath $broadRoot -Recurse -Force }
}

$claudeTestRoot = Join-Path ([IO.Path]::GetTempPath()) "agent-state-claude-$([guid]::NewGuid())"
try {
    $claudeProfileRoot = Join-Path $claudeTestRoot 'profile'
    $claudeHome = Join-Path $claudeProfileRoot '.claude'
    $claudeDesktop = Join-Path $claudeProfileRoot 'AppData\Roaming\Claude'
    $profilePath = Join-Path $claudeProfileRoot '.claude.json'
    $profileBackupPath = Join-Path $claudeProfileRoot '.claude.json.backup'
    $historyBackupPath = Join-Path $claudeHome 'backups\.claude.json.backup.1'
    $repoSentinel = Join-Path $claudeTestRoot 'repository\worktree.txt'
    foreach ($directory in @(
        (Split-Path -Parent $repoSentinel),
        (Join-Path $claudeHome 'projects\old-project\memory'),
        (Join-Path $claudeHome 'plugins\kept'),
        (Split-Path -Parent $historyBackupPath),
        (Join-Path $claudeDesktop 'claude-code-sessions'),
        (Join-Path $claudeDesktop 'Cache'),
        (Join-Path $claudeDesktop 'Local Storage\leveldb')
    )) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    Set-Content -LiteralPath $repoSentinel -Value 'keep repository' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeHome 'settings.json') -Value '{"theme":"keep"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeHome '.credentials.json') -Value '{"oauth":"keep"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeHome '.last-cleanup') -Value 'marker' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeHome 'plugins\kept\config.json') -Value '{"enabled":true}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeHome 'projects\old-project\memory\MEMORY.md') -Value 'remove memory' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeDesktop 'claude-code-sessions\session.json') -Value 'remove session' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeDesktop 'Cache\entry') -Value 'remove cache path' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeDesktop 'Local Storage\leveldb\000001.ldb') -Value 'selectedFolder=D:\old-project' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $claudeDesktop 'config.json') -Value '{"locale":"fr-FR","oauth:tokenCache":"keep"}' -Encoding utf8NoBOM
    $profileJson = $claudeProfile | ConvertTo-Json -Depth 20
    foreach ($path in @($profilePath, $profileBackupPath, $historyBackupPath)) {
        Set-Content -LiteralPath $path -Value $profileJson -Encoding utf8NoBOM
    }
    Set-Content -LiteralPath (Join-Path $claudeDesktop 'claude_desktop_config.json') -Value ($desktopConfig | ConvertTo-Json -Depth 20) -Encoding utf8NoBOM

    $claudePlanParameters = @{
        Scope = 'Claude'
        UserProfileRoot = $claudeProfileRoot
        ClaudeHome = $claudeHome
        ClaudeDesktopData = $claudeDesktop
    }
    $claudePlan = Get-AgentStateCleanupPlan @claudePlanParameters
    $sessionPath = Join-Path $claudeDesktop 'claude-code-sessions\session.json'
    $sessionHash = (Get-FileHash -LiteralPath $sessionPath).Hash
    $profileHash = (Get-FileHash -LiteralPath $profilePath).Hash
    $profileTime = (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc
    $preview = Invoke-AgentStateCleanupPlan -Plan $claudePlan
    Assert-Equal $false $preview.Applied 'Preview reports no apply'
    Assert-Equal $sessionHash (Get-FileHash -LiteralPath $sessionPath).Hash 'Preview preserves session file'
    Assert-Equal $profileHash (Get-FileHash -LiteralPath $profilePath).Hash 'Preview preserves mixed state file'
    Assert-Equal $profileTime (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc 'Preview preserves mixed state timestamp'

    # Without the exact phrase the reset refuses and nothing changes.
    Assert-Throws {
        Invoke-AgentStateCleanupPlan -Plan $claudePlan -Apply -RunningProcessNames @('explorer')
    } 'exact confirmation phrase' 'Reset without the confirmation phrase is refused'
    Assert-Throws {
        Invoke-AgentStateCleanupPlan -Plan $claudePlan -Apply -Confirmation 'reset local ai sessions' -RunningProcessNames @('explorer')
    } 'exact confirmation phrase' 'The confirmation phrase is case sensitive'
    Assert-Equal $true (Test-Path -LiteralPath $sessionPath) 'A refused reset keeps the session file'
    Assert-Equal $profileHash (Get-FileHash -LiteralPath $profilePath).Hash 'A refused reset keeps the mixed state file'

    $claudeResult = Invoke-AgentStateCleanupPlan -Plan $claudePlan -Apply -Confirmation 'RESET LOCAL AI SESSIONS' -RunningProcessNames @('explorer')
    Assert-Equal $true $claudeResult.Applied 'Claude cleanup applies without calling an installed executable'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $claudeHome 'projects')) 'Claude projects and automatic memory are removed'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $claudeDesktop 'claude-code-sessions')) 'Claude Desktop sessions are removed'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $claudeDesktop 'Cache')) 'Claude Desktop path cache is removed'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $claudeDesktop 'Local Storage\leveldb')) 'Claude Desktop local storage and folder references are removed'
    Assert-Equal 'keep repository' (Get-Content -Raw -LiteralPath $repoSentinel).Trim() 'Repositories are not traversed'
    Assert-Equal '{"theme":"keep"}' (Get-Content -Raw -LiteralPath (Join-Path $claudeHome 'settings.json')).Trim() 'Claude settings are preserved'
    Assert-Equal '{"oauth":"keep"}' (Get-Content -Raw -LiteralPath (Join-Path $claudeHome '.credentials.json')).Trim() 'Claude credentials are preserved'
    Assert-Equal 'marker' (Get-Content -Raw -LiteralPath (Join-Path $claudeHome '.last-cleanup')).Trim() 'Claude cleanup marker is preserved'
    Assert-Equal '{"enabled":true}' (Get-Content -Raw -LiteralPath (Join-Path $claudeHome 'plugins\kept\config.json')).Trim() 'Claude plugins are preserved'
    Assert-Equal '{"locale":"fr-FR","oauth:tokenCache":"keep"}' (Get-Content -Raw -LiteralPath (Join-Path $claudeDesktop 'config.json')).Trim() 'Claude Desktop account and UI configuration are preserved'
    foreach ($path in @($profilePath, $profileBackupPath, $historyBackupPath)) {
        $cleanProfile = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 20
        Assert-Equal 0 @($cleanProfile.projects.PSObject.Properties).Count 'Claude project entries are cleared from live and backup profiles'
        Assert-Equal 'account-1' $cleanProfile.oauthAccount.accountUuid 'Claude account is preserved in live and backup profiles'
    }
    Assert-Equal $true (Test-Path -LiteralPath (Split-Path -Parent $historyBackupPath)) 'Claude backup directory is preserved'
    $cleanDesktop = Get-Content -Raw -LiteralPath (Join-Path $claudeDesktop 'claude_desktop_config.json') | ConvertFrom-Json -Depth 20
    Assert-Equal 0 @($cleanDesktop.preferences.epitaxyPrefs.'epitaxy-folder-permission-mode.account-1'.PSObject.Properties).Count 'Claude Desktop project permissions are cleared on apply'
    Assert-Equal 'D:\worktrees\sample' $cleanDesktop.preferences.'chillingSlothLocation.customPath' 'Claude Desktop worktree preference survives apply'
    $secondClaudePlan = Get-AgentStateCleanupPlan @claudePlanParameters
    $secondClaudeApply = Invoke-AgentStateCleanupPlan -Plan $secondClaudePlan -Apply -Confirmation 'RESET LOCAL AI SESSIONS' -RunningProcessNames @('explorer')
    Assert-Equal 0 $secondClaudeApply.RemovedTargets 'Second Claude apply has no file target to remove'
    Assert-Equal 0 $secondClaudeApply.ChangedStateFiles 'Second Claude apply is idempotent'
} finally {
    if (Test-Path -LiteralPath $claudeTestRoot) { Remove-Item -LiteralPath $claudeTestRoot -Recurse -Force }
}

$linkRoot = Join-Path ([IO.Path]::GetTempPath()) "agent-state-link-$([guid]::NewGuid())"
try {
    $linkClaude = Join-Path $linkRoot '.claude'
    $linkTarget = Join-Path $linkRoot 'external-sessions'
    $null = New-Item -ItemType Directory -Path $linkClaude -Force
    $null = New-Item -ItemType Directory -Path $linkTarget -Force
    Set-Content -LiteralPath (Join-Path $linkClaude '.credentials.json') -Value '{"oauth":"keep"}' -Encoding utf8NoBOM
    $null = New-Item -ItemType Junction -Path (Join-Path $linkClaude 'sessions') -Target $linkTarget
    Assert-Throws {
        Get-AgentStateCleanupPlan -Scope Claude -UserProfileRoot $linkRoot -ClaudeHome $linkClaude
    } 'reparse point' 'Reparse-point cleanup target is rejected'
    Remove-Item -LiteralPath (Join-Path $linkClaude 'sessions') -Force
} finally {
    if (Test-Path -LiteralPath $linkRoot) { Remove-Item -LiteralPath $linkRoot -Recurse -Force }
}

$fakeRepoRoot = Join-Path ([IO.Path]::GetTempPath()) "agent-state-fake-repo-$([guid]::NewGuid())"
try {
    $fakeProfile = Join-Path $fakeRepoRoot 'profile'
    $fakeRepo = Join-Path $fakeRepoRoot 'repository'
    $null = New-Item -ItemType Directory -Path $fakeProfile -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'projects\real-source') -Force
    Set-Content -LiteralPath (Join-Path $fakeRepo 'CLAUDE.md') -Value 'project instructions' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $fakeRepo 'settings.json') -Value '{"project":true}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $fakeRepo 'projects\real-source\keep.txt') -Value 'repository work' -Encoding utf8NoBOM
    Assert-Throws {
        Get-AgentStateCleanupPlan -Scope Claude -UserProfileRoot $fakeProfile -ClaudeHome $fakeRepo
    } 'Unrecognized Claude state root' 'A repository cannot masquerade as Claude home'
    Assert-Equal 'repository work' (Get-Content -Raw -LiteralPath (Join-Path $fakeRepo 'projects\real-source\keep.txt')).Trim() 'Rejected repository content is untouched'
} finally {
    if (Test-Path -LiteralPath $fakeRepoRoot) { Remove-Item -LiteralPath $fakeRepoRoot -Recurse -Force }
}

$ancestorRoot = Join-Path ([IO.Path]::GetTempPath()) "agent-state-ancestor-$([guid]::NewGuid())"
$ancestorExternal = Join-Path ([IO.Path]::GetTempPath()) "agent-state-ancestor-external-$([guid]::NewGuid())"
$ancestorJunction = Join-Path $ancestorRoot 'profile\linked'
try {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ancestorJunction) -Force
    $ancestorClaude = Join-Path $ancestorExternal '.claude'
    $null = New-Item -ItemType Directory -Path (Join-Path $ancestorClaude 'sessions') -Force
    Set-Content -LiteralPath (Join-Path $ancestorClaude '.credentials.json') -Value 'test-installation' -Encoding utf8NoBOM
    $null = New-Item -ItemType Junction -Path $ancestorJunction -Target $ancestorExternal
    Assert-Throws {
        Get-AgentStateCleanupPlan -Scope Claude -UserProfileRoot (Join-Path $ancestorRoot 'profile') -ClaudeHome (Join-Path $ancestorJunction '.claude')
    } 'reparse point ancestor' 'A reparse point above the agent root is rejected'
} finally {
    if (Test-Path -LiteralPath $ancestorJunction) { Remove-Item -LiteralPath $ancestorJunction -Force }
    if (Test-Path -LiteralPath $ancestorRoot) { Remove-Item -LiteralPath $ancestorRoot -Recurse -Force }
    if (Test-Path -LiteralPath $ancestorExternal) { Remove-Item -LiteralPath $ancestorExternal -Recurse -Force }
}

Write-Host 'agent-state-maintenance.tests.ps1: PASS' -ForegroundColor Green
