# Shared fixtures of the update tests: a synthetic source and an empty target.

$script:RealScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Git([string]$Path, [string[]]$Arguments) {
    $log = & git -C $Path -c user.name=Test -c user.email=test@example.invalid @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in '$Path': $log" }
}

function New-GitRepository([string]$Path) {
    $null = New-Item -ItemType Directory -Path $Path -Force
    Invoke-Git $Path @('init', '--quiet')
}

function Save-Commit([string]$Path, [string]$Message) {
    Invoke-Git $Path @('add', '--all')
    Invoke-Git $Path @('commit', '--quiet', '-m', $Message)
}

function Set-FixtureFile([string]$Root, [string]$Relative, [string]$Content) {
    $path = Join-Path $Root $Relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

# A source holding the real update program and the library it runs on, plus
# one file per owned area, tagged v0.1.0.
function New-SourceFixture([string]$Root) {
    New-GitRepository $Root
    foreach ($name in @('version.ps1', 'manifest.ps1', 'script-output.ps1', 'action-summary.ps1')) {
        $destination = Join-Path $Root "scripts/lib/$name"
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
        Copy-Item -LiteralPath (Join-Path $script:RealScriptsDir "lib/$name") -Destination $destination
    }
    Copy-Item -LiteralPath (Join-Path $script:RealScriptsDir 'settings/update.ps1') -Destination (New-Item -ItemType Directory -Path (Join-Path $Root 'scripts/settings') -Force | Join-Path -ChildPath 'update.ps1')
    Set-FixtureFile $Root 'scripts/menu.ps1' "# menu`n"
    Set-FixtureFile $Root 'scripts/lib/sample.ps1' "# sample v1`n"
    Set-FixtureFile $Root 'scripts/alpha/one.ps1' "# one`n"
    Set-FixtureFile $Root 'scripts/beta/two.ps1' "# two`n"
    Set-FixtureFile $Root 'scripts/tests/t.tests.ps1' "# a test`n"
    Save-Commit $Root 'first'
    Invoke-Git $Root @('tag', '-a', 'v0.1.0', '-m', 'Version 0.1.0')
}

function New-TargetFixture([string]$Path) {
    New-GitRepository $Path
    Invoke-Git $Path @('commit', '--quiet', '--allow-empty', '-m', 'first')
}

# Runs a script in its own process and returns its text and exit code.
function Invoke-Script([string]$Script, [string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $Script @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}
