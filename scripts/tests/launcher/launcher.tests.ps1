$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MenuPath = Join-Path $ScriptsDir 'menu.ps1'
$FixtureDir = Join-Path $ScriptsDir 'tests\fixtures\script-discovery'

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

# The entry serves any repository: the fixture scripts in a fresh one.
$root = Join-Path ([IO.Path]::GetTempPath()) "launcher-entry-$([guid]::NewGuid())"
$outside = Join-Path ([IO.Path]::GetTempPath()) "launcher-outside-$([guid]::NewGuid())"
try {
    $scriptsRoot = Join-Path $root 'scripts'
    $null = New-Item -ItemType Directory -Path $scriptsRoot
    & git -C $root init -q
    Copy-Item -Path (Join-Path $FixtureDir '*') -Destination $scriptsRoot -Recurse
    foreach ($name in @('glued-requires.ps1', 'dot-word.ps1', 'two-axes.ps1')) {
        Remove-Item -LiteralPath (Join-Path $scriptsRoot $name) -Force
    }
    $header = "<#`n.SYNOPSIS`n    Leaves`n.DESCRIPTION`n    Fixture.`n#>`n"
    [IO.File]::WriteAllText((Join-Path $scriptsRoot 'leaves.ps1'), $header + "Write-Output 'before'`nexit 3`n")

    $list = @(& pwsh -NoProfile -File $MenuPath -List -ScriptsRoot $scriptsRoot)
    Assert-Equal 0 $LASTEXITCODE '-List exits cleanly'
    $rows = @($list | ForEach-Object { $_ -split "`t" })
    $ids = @($list | ForEach-Object { ($_ -split "`t")[0] })
    Assert-True ($ids -contains 'gamma.1') '-List names every Action by its id'
    Assert-Equal 2 @($ids | Where-Object { $_ -eq 'beta.0' }).Count '-List prints one row per Variant'
    $ship = @($list | Where-Object { $_.StartsWith("gamma.1`t") })[0] -split "`t"
    Assert-Equal 'Ship' $ship[1] '-List gives the Action label'
    Assert-Equal 'gamma.ps1' $ship[2] '-List gives the script'
    Assert-Equal '-Publish' $ship[3] '-List gives the arguments'
    Assert-True (@($list | Where-Object { $_ -match 'tools/deep/zeta\.ps1' }).Count -eq 1) '-List reaches nested folders'

    $run = @(& pwsh -NoProfile -File $MenuPath -Run gamma.1 -ScriptsRoot $scriptsRoot)
    Assert-Equal 0 $LASTEXITCODE '-Run of a successful Action exits 0'
    Assert-True (($run -join "`n") -match 'gamma True') '-Run prints the Journal'
    Assert-True (($run -join "`n") -match 'Result: Success') '-Run prints the conclusion'

    $run = @(& pwsh -NoProfile -File $MenuPath -Run beta.0 -Variant Debug -ScriptsRoot $scriptsRoot)
    Assert-True (($run -join "`n") -match 'beta Debug') '-Run passes the Variant'

    $null = @(& pwsh -NoProfile -File $MenuPath -Run leaves.0 -ScriptsRoot $scriptsRoot)
    Assert-Equal 1 $LASTEXITCODE '-Run of a failed Action exits 1'

    $null = @(& pwsh -NoProfile -File $MenuPath -Run missing.0 -ScriptsRoot $scriptsRoot 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) '-Run of an unknown Action fails'

    foreach ($snapshot in @('Menu', 'Confirmation', 'Execution', 'Logs')) {
        $frame = @(& pwsh -NoProfile -File $MenuPath -Snapshot $snapshot -ScriptsRoot $scriptsRoot)
        Assert-Equal 0 $LASTEXITCODE "-Snapshot $snapshot exits cleanly"
        Assert-True ($frame.Count -ge 8) "-Snapshot $snapshot prints a frame"
    }
    $menu = @(& pwsh -NoProfile -File $MenuPath -Snapshot Menu -ScriptsRoot $scriptsRoot) -join "`n"
    Assert-True ($menu -match 'Tooling') 'the Menu snapshot offers the folders'
    Assert-True ($menu -match 'Logs') 'the Menu snapshot offers the Logs'
    Assert-True ($menu -match 'Quit') 'the Menu snapshot closes with Quit'
    $level = @(& pwsh -NoProfile -File $MenuPath -Snapshot Level -LevelPath tools -ScriptsRoot $scriptsRoot) -join "`n"
    Assert-True ($level -match 'Epsilon' -or $level -match 'epsilon') 'the Level snapshot shows a folder'
    Assert-True ($menu -match 'SCRIPTS') 'the Menu snapshot opens with the logo'
    Assert-True ($menu.Contains((Split-Path -Leaf $root))) 'the Banner names the repository folder'

    # From a worktree the Banner still names the repository, not the subject.
    & git -C $root add -A 2>&1 | Out-Null
    & git -C $root -c user.name=Test -c user.email=test@example.invalid commit --quiet -m 'fixtures' 2>&1 | Out-Null
    $worktree = Join-Path $outside 'subject'
    & git -C $root worktree add --quiet $worktree 2>&1 | Out-Null
    $fromWorktree = @(& pwsh -NoProfile -File $MenuPath -Snapshot Menu -ScriptsRoot (Join-Path $worktree 'scripts')) -join "`n"
    Assert-Equal 0 $LASTEXITCODE 'the entry serves a worktree'
    Assert-True ($fromWorktree.Contains((Split-Path -Leaf $root)) -and -not $fromWorktree.Contains('subject')) 'a worktree is named after its repository'
    & git -C $root worktree remove --force $worktree 2>&1 | Out-Null

    # Outside any repository the launcher has no root to run the scripts under.
    $outsideScripts = Join-Path $outside 'scripts'
    $null = New-Item -ItemType Directory -Path $outsideScripts
    Copy-Item -Path (Join-Path $FixtureDir 'alpha.ps1') -Destination $outsideScripts
    $null = @(& pwsh -NoProfile -File $MenuPath -List -ScriptsRoot $outsideScripts 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) 'a scripts folder outside a git repository is refused'

    # Windows PowerShell reads the entry and hands over to PowerShell 7.
    $legacy = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $legacy) {
        $frame = @(& $legacy.Source -NoProfile -File $MenuPath -Snapshot Menu -ScriptsRoot $scriptsRoot)
        Assert-Equal 0 $LASTEXITCODE 'the entry runs under Windows PowerShell'
        Assert-True (($frame -join "`n") -match 'Quit') 'Windows PowerShell gets the same frame'
        $null = @(& $legacy.Source -NoProfile -File $MenuPath -Run leaves.0 -ScriptsRoot $scriptsRoot)
        Assert-Equal 1 $LASTEXITCODE 'Windows PowerShell relays the exit code'
    } else {
        Write-Host 'launcher.tests.ps1: Windows PowerShell absent, bootstrap not exercised' -ForegroundColor Yellow
    }

    $entryBytes = [IO.File]::ReadAllBytes($MenuPath)
    Assert-True (@($entryBytes | Where-Object { $_ -gt 127 }).Count -eq 0) 'the entry is ASCII'
    Assert-True ((Get-Content -LiteralPath $MenuPath -Raw) -notmatch '(?m)^\s*param\s*\(') 'the entry declares no parameters'

    Write-Host 'launcher.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    if (Test-Path -LiteralPath $outside) { Remove-Item -LiteralPath $outside -Recurse -Force }
}
