$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'setup\scaffold.ps1'

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Scaffold([string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "scaffold-$([guid]::NewGuid())"
try {
    $null = New-Item -ItemType Directory -Path $root
    & git -C $root init --quiet
    & git -C $root config user.name 'Jane Holder'
    & git -C $root config user.email 'jane@example.invalid'

    # Preview: the plan is listed and nothing is created.
    $preview = Invoke-Scaffold @('-Target', $root)
    Assert-Equal 0 $preview.ExitCode 'the preview succeeds'
    Assert-True ($preview.Text -match 'create\s+docs/') 'the preview lists the folders it would create'
    Assert-True ($preview.Text -match 'create\s+LICENSE') 'the preview lists the license it would create'
    Assert-True ($preview.Text -match 'Preview:') 'the preview says it is a preview'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $root -Force | Where-Object Name -ne '.git').Count 'the preview creates nothing'

    # Apply: folders with a placeholder, files from the templates.
    $apply = Invoke-Scaffold @('-Target', $root, '-Apply')
    Assert-Equal 0 $apply.ExitCode 'apply succeeds'
    foreach ($folder in @('docs', 'src', 'tests')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $root "$folder\.gitkeep") -PathType Leaf) "$folder holds a .gitkeep"
    }
    foreach ($file in @('AGENTS.md', 'CLAUDE.md', '.gitignore', '.gitattributes', 'CONTRIBUTING.md', 'LICENSE')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf) "$file is created"
    }
    Assert-Equal '@AGENTS.md' ([IO.File]::ReadAllText((Join-Path $root 'CLAUDE.md')).Trim()) 'CLAUDE.md imports AGENTS.md'
    $folderName = Split-Path -Leaf $root
    Assert-True ([IO.File]::ReadAllText((Join-Path $root 'AGENTS.md')).StartsWith("# AGENTS.md — $folderName")) 'AGENTS.md carries the folder name'
    $license = [IO.File]::ReadAllText((Join-Path $root 'LICENSE'))
    Assert-True ($license -match 'MIT License') 'the default license is MIT'
    Assert-True ($license.Contains('Jane Holder')) 'the license names the git user as holder'
    Assert-True ($license.Contains([string](Get-Date).Year)) 'the license carries the current year'
    Assert-True (-not ($license -match '\{\{')) 'no placeholder is left in the license'
    Assert-True ($apply.Text -match 'Created\s*:') 'the summary lists what was created'

    # A second run overwrites nothing.
    [IO.File]::WriteAllText((Join-Path $root 'AGENTS.md'), "mine`n")
    $again = Invoke-Scaffold @('-Target', $root, '-Apply')
    Assert-Equal 0 $again.ExitCode 'a second apply succeeds'
    Assert-Equal "mine`n" ([IO.File]::ReadAllText((Join-Path $root 'AGENTS.md'))) 'an existing file is left as it is'
    Assert-True ($again.Text -match 'Nothing to scaffold') 'a second apply says there is nothing to do'
    Assert-True ($again.Text -match 'kept\s+AGENTS\.md') 'an existing file is listed as kept'

    # No license: no LICENSE file.
    $noLicenseRoot = Join-Path ([IO.Path]::GetTempPath()) "scaffold-$([guid]::NewGuid())"
    try {
        $null = New-Item -ItemType Directory -Path $noLicenseRoot
        & git -C $noLicenseRoot init --quiet
        $none = Invoke-Scaffold @('-Target', $noLicenseRoot, '-Apply', '-License', 'None', '-Folders', 'docs')
        Assert-Equal 0 $none.ExitCode 'scaffolding without a license succeeds'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $noLicenseRoot 'LICENSE'))) 'License None writes no LICENSE'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $noLicenseRoot 'src'))) '-Folders replaces the default folders'
        Assert-True (Test-Path -LiteralPath (Join-Path $noLicenseRoot 'docs\.gitkeep')) '-Folders names the folders created'
    } finally {
        if (Test-Path -LiteralPath $noLicenseRoot) { Remove-Item -LiteralPath $noLicenseRoot -Recurse -Force }
    }

    # GPL carries no placeholder and needs no holder.
    $gplRoot = Join-Path ([IO.Path]::GetTempPath()) "scaffold-$([guid]::NewGuid())"
    try {
        $null = New-Item -ItemType Directory -Path $gplRoot
        & git -C $gplRoot init --quiet
        $gpl = Invoke-Scaffold @('-Target', $gplRoot, '-Apply', '-License', 'GPL-3.0', '-Folders', 'docs', '-Holder', 'Someone')
        Assert-Equal 0 $gpl.ExitCode 'scaffolding with the GPL succeeds'
        Assert-True ([IO.File]::ReadAllText((Join-Path $gplRoot 'LICENSE')) -match 'GNU GENERAL PUBLIC LICENSE') 'the GPL text is written'
    } finally {
        if (Test-Path -LiteralPath $gplRoot) { Remove-Item -LiteralPath $gplRoot -Recurse -Force }
    }

    # An unknown license fails before anything is created.
    $badRoot = Join-Path ([IO.Path]::GetTempPath()) "scaffold-$([guid]::NewGuid())"
    try {
        $null = New-Item -ItemType Directory -Path $badRoot
        & git -C $badRoot init --quiet
        $bad = Invoke-Scaffold @('-Target', $badRoot, '-Apply', '-License', 'Apache')
        Assert-Equal 1 $bad.ExitCode 'an unknown license fails'
        Assert-True ($bad.Text -match 'Failed') 'the failure ends with a Failed summary'
        Assert-True ($bad.Text -match "Unknown license 'Apache'") 'the failure names the license'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $badRoot -Force | Where-Object Name -ne '.git').Count 'a failure creates nothing'
    } finally {
        if (Test-Path -LiteralPath $badRoot) { Remove-Item -LiteralPath $badRoot -Recurse -Force }
    }

    Write-Host 'scaffold.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
