$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Pack([string]$Root, [string]$Script, [string[]]$Arguments) {
    $path = Join-Path $Root "scripts\setup\$Script"
    $text = @(& pwsh -NoProfile -File $path @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}

# Setting a variable to $null through .NET leaves it defined and empty, which
# git reads as an empty identity; removing it takes the Env: drive.
function Set-EnvironmentValue([string]$Name, $Value) {
    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        Set-Item -LiteralPath "Env:$Name" -Value $Value
    }
}

# Runs a git commit and returns its exit code with its messages; a hook that
# rejects the commit prints on stderr, which must not stop this test.
function Invoke-Commit([string]$Root, [string]$Message, [hashtable]$Environment = @{}) {
    $messagePath = Join-Path $Root '.git\TEST_MSG'
    [IO.File]::WriteAllText($messagePath, $Message)
    # The identity variables and the global config of the machine running the
    # test would override or add to the fixture's own config (a global hook
    # would run beside the ones under test), so they are cleared or replaced
    # by an empty config unless the case sets them itself.
    $identityVariables = @('GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL')
    $effective = @{}
    foreach ($key in $identityVariables) { $effective[$key] = $null }
    $emptyConfig = Join-Path $Root '.git\TEST_EMPTY_CONFIG'
    [IO.File]::WriteAllText($emptyConfig, '')
    $effective['GIT_CONFIG_GLOBAL'] = $emptyConfig
    $effective['GIT_CONFIG_NOSYSTEM'] = '1'
    foreach ($key in $Environment.Keys) { $effective[$key] = $Environment[$key] }
    $saved = @{}
    foreach ($key in $effective.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key)
        Set-EnvironmentValue $key $effective[$key]
    }
    try {
        $text = @(& git -C $Root commit --quiet -F $messagePath 2>&1) -join "`n"
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
    } finally {
        foreach ($key in $saved.Keys) { Set-EnvironmentValue $key $saved[$key] }
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "install-hooks-$([guid]::NewGuid())"
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'scripts')
    & git -C $root init --quiet
    & git -C $root config user.name 'Test Maintainer'
    & git -C $root config user.email 'maintainer@example.invalid'
    Copy-Item -LiteralPath (Join-Path $ScriptsDir 'lib') -Destination (Join-Path $root 'scripts\lib') -Recurse
    Copy-Item -LiteralPath (Join-Path $ScriptsDir 'setup') -Destination (Join-Path $root 'scripts\setup') -Recurse

    $hooksDir = Join-Path $root '.git\hooks'
    $existing = "#!/bin/sh`necho my own hook`n"
    [IO.File]::WriteAllText((Join-Path $hooksDir 'pre-commit'), $existing)

    # Preview changes nothing.
    $preview = Invoke-Pack $root 'install-hooks.ps1' @('-Target', $root)
    Assert-Equal 0 $preview.ExitCode 'the preview succeeds'
    Assert-True ($preview.Text -match 'install\s+pre-commit') 'the preview lists the hooks it would install'
    Assert-True ($preview.Text -match 'pre-commit\.bak') 'the preview says the existing hook would be backed up'
    Assert-True ($preview.Text -match 'would be set') 'the preview says the merge driver would be set'
    Assert-Equal $existing ([IO.File]::ReadAllText((Join-Path $hooksDir 'pre-commit'))) 'the preview leaves the existing hook alone'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $hooksDir 'commit-msg'))) 'the preview installs nothing'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $hooksDir 'pre-commit.bak'))) 'the preview backs nothing up'
    Assert-Equal '' ((& git -C $root config --local --get merge.ours.driver) -join '') 'the preview sets no merge driver'

    # Apply installs, backs up and registers the driver.
    $apply = Invoke-Pack $root 'install-hooks.ps1' @('-Target', $root, '-Apply')
    Assert-Equal 0 $apply.ExitCode 'apply succeeds'
    foreach ($hook in @('pre-commit', 'commit-msg')) {
        $installed = [IO.File]::ReadAllText((Join-Path $hooksDir $hook))
        Assert-True $installed.StartsWith('#!/bin/sh') "$hook is installed"
        Assert-True (-not $installed.Contains("`r")) "$hook has LF line endings"
    }
    Assert-Equal $existing ([IO.File]::ReadAllText((Join-Path $hooksDir 'pre-commit.bak'))) 'the existing hook is kept as pre-commit.bak'
    Assert-Equal 'true' ((& git -C $root config --local --get merge.ours.driver) -join '') 'the merge driver is registered in the repository config'
    Assert-True ($apply.Text -match 'Backed up\s*:\s*pre-commit\.bak') 'the summary lists the backup'

    # A second apply has nothing to do and keeps the backup intact.
    $again = Invoke-Pack $root 'install-hooks.ps1' @('-Target', $root, '-Apply')
    Assert-Equal 0 $again.ExitCode 'a second apply succeeds'
    Assert-True ($again.Text -match 'already installed and up to date') 'a second apply says everything is current'
    Assert-Equal $existing ([IO.File]::ReadAllText((Join-Path $hooksDir 'pre-commit.bak'))) 'a second apply does not overwrite the backup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $hooksDir 'pre-commit.bak.1'))) 'a second apply makes no second backup'

    # The hooks work end to end.
    [IO.File]::WriteAllText((Join-Path $root 'notes.txt'), "first`n")
    & git -C $root add notes.txt scripts 2>$null
    $trailer = Invoke-Commit $root "Add notes`n`nCo-Authored-By: Someone Else <someone@example.invalid>`n"
    Assert-True ($trailer.ExitCode -ne 0) 'a commit with a Co-Authored-By trailer is rejected'
    Assert-True ($trailer.Text -match 'attribution\s+is\s+forbidden') "the rejection says why: $($trailer.Text)"
    & git -C $root rev-parse --verify --quiet HEAD *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'a rejected commit leaves no commit'

    $foreign = Invoke-Commit $root "Add notes`n" @{ GIT_AUTHOR_NAME = 'Somebody Else' }
    Assert-True ($foreign.ExitCode -ne 0) 'a commit under another identity is rejected'
    Assert-True ($foreign.Text -match 'author\s+identity') 'the rejection names the identity'

    $accepted = Invoke-Commit $root "Add notes`n"
    Assert-Equal 0 $accepted.ExitCode 'a clean commit is accepted'
    $tree = (& git -C $root show 'HEAD:TREE.md') -join "`n"
    Assert-True ($tree.Contains('notes.txt')) 'the pre-commit hook put a regenerated TREE.md in the commit'
    Assert-True ($tree.Contains('update-tree.ps1')) 'the regenerated tree lists the pack'

    # Failure: an unknown hook name.
    $unknown = Invoke-Pack $root 'install-hooks.ps1' @('-Target', $root, '-Apply', '-Hooks', 'post-merge')
    Assert-Equal 1 $unknown.ExitCode 'an unknown hook fails'
    Assert-True ($unknown.Text -match "Unknown hook 'post-merge'") 'the failure names the hook'

    Write-Host 'install-hooks.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
