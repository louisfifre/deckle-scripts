$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'setup\update-tree.ps1'

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-UpdateTree([string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "update-tree-$([guid]::NewGuid())"
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs'), (Join-Path $root 'tools')
    & git -C $root init --quiet

    [IO.File]::WriteAllText((Join-Path $root 'docs\README.md'), "---`nname: Documentation`ndescription: Where the notes live.`n---`n`nBody.`n")
    [IO.File]::WriteAllText((Join-Path $root 'docs\plain.md'), "No front matter here.`n")
    [IO.File]::WriteAllText((Join-Path $root 'tools\hello.ps1'), "<#`n.SYNOPSIS`n    Say hello`n.DESCRIPTION`n    Greets the caller politely.`n#>`n`n'hello'`n")
    [IO.File]::WriteAllText((Join-Path $root 'tools\hidden.ps1'), "'no header here'`n")
    [IO.File]::WriteAllText((Join-Path $root 'untracked.txt'), "never added`n")
    & git -C $root add docs tools 2>$null
    $treePath = Join-Path $root 'TREE.md'

    # Preview reports the change and writes nothing.
    $preview = Invoke-UpdateTree @('-Target', $root)
    Assert-Equal 0 $preview.ExitCode 'the preview succeeds'
    Assert-True (-not (Test-Path -LiteralPath $treePath)) 'the preview writes nothing'
    Assert-True ($preview.Text -match 'would change') 'the preview says TREE.md would change'
    Assert-True ($preview.Text -match 'Changed\s*:\s*yes') 'the preview summary counts a change'
    Assert-True ($preview.Text -match 'Files\s*:\s*5') 'the summary counts the tracked files plus TREE.md'

    # Apply writes the tree with both annotations.
    $apply = Invoke-UpdateTree @('-Target', $root, '-Apply')
    Assert-Equal 0 $apply.ExitCode 'apply succeeds'
    Assert-True (Test-Path -LiteralPath $treePath -PathType Leaf) 'apply writes TREE.md'
    $bytes = [IO.File]::ReadAllBytes($treePath)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'TREE.md has no BOM'
    Assert-True ($bytes -notcontains 13) 'TREE.md has LF line endings only'
    $tree = [IO.File]::ReadAllText($treePath)
    $folderName = Split-Path -Leaf $root
    Assert-True ($tree.StartsWith("# Tree — $folderName`n")) 'TREE.md is titled with the folder name'
    Assert-True ($tree -match 'README\.md  — Documentation Where the notes live\.') 'a Markdown file is annotated with its front matter'
    Assert-True ($tree -match 'hello\.ps1  — Say hello Greets the caller politely\.') 'a script is annotated with its Header'
    Assert-True ($tree -match '├── plain\.md\r?\n') 'a Markdown file without front matter stays bare'
    Assert-True ($tree -match 'hidden\.ps1\r?\n') 'a script without a Header stays bare'
    Assert-True (-not $tree.Contains('untracked.txt')) 'an untracked file is not listed'

    # A second run finds nothing to change and leaves the file alone.
    $stamp = (Get-Item -LiteralPath $treePath).LastWriteTimeUtc
    Start-Sleep -Milliseconds 50
    $again = Invoke-UpdateTree @('-Target', $root, '-Apply')
    Assert-Equal 0 $again.ExitCode 'a second apply succeeds'
    Assert-True ($again.Text -match 'Changed\s*:\s*no') 'a second apply reports no change'
    Assert-Equal $stamp (Get-Item -LiteralPath $treePath).LastWriteTimeUtc 'an unchanged tree is not rewritten'

    # A new tracked file makes the tree stale again, and the preview sees it.
    [IO.File]::WriteAllText((Join-Path $root 'docs\more.md'), "More.`n")
    & git -C $root add docs 2>$null
    $stale = Invoke-UpdateTree @('-Target', $root)
    Assert-True ($stale.Text -match 'Changed\s*:\s*yes') 'the preview notices a new tracked file'
    Assert-True (-not ([IO.File]::ReadAllText($treePath)).Contains('more.md')) 'the preview leaves TREE.md alone'

    # Failure: a folder that is not a repository.
    $plain = Join-Path ([IO.Path]::GetTempPath()) "update-tree-plain-$([guid]::NewGuid())"
    try {
        $null = New-Item -ItemType Directory -Path $plain
        $failed = Invoke-UpdateTree @('-Target', $plain, '-Apply')
        Assert-Equal 1 $failed.ExitCode 'a folder outside a repository fails'
        Assert-True ($failed.Text -match 'Failed') 'the failure ends with a Failed summary'
    } finally {
        if (Test-Path -LiteralPath $plain) { Remove-Item -LiteralPath $plain -Recurse -Force }
    }

    Write-Host 'update-tree.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
