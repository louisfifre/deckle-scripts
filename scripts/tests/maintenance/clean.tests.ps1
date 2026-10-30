$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
$CleanPath = Join-Path $ScriptsDir 'maintenance\clean.ps1'
. (Join-Path $LibDir 'build-outputs.ps1')

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Invoke-Git([string]$Root, [string[]]$Arguments) {
    & git -C $Root -c user.name=Test -c user.email=test@example.invalid @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in $Root" }
}

function New-TextFile([string]$Path, [string]$Content = 'x') {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, $Content)
}

$root = Join-Path ([IO.Path]::GetTempPath()) "clean-$([guid]::NewGuid())"
$repo = Join-Path $root 'repo'
$outside = Join-Path $root 'outside'
$plain = Join-Path $root 'plain'
try {
    $null = New-Item -ItemType Directory -Path $repo, $outside, $plain
    Invoke-Git $repo @('init', '--quiet')

    # Tracked files: a .NET project and a hand-written script in a folder the
    # .gitignore still lists, which the third lock must protect.
    New-TextFile (Join-Path $repo 'App.csproj') '<Project />'
    New-TextFile (Join-Path $repo 'src\Program.cs')
    New-TextFile (Join-Path $repo '.gitignore') "bin/`nobj/`npublish/`nnode_modules/`n"
    New-TextFile (Join-Path $repo 'publish\keep.txt') 'tracked'
    Invoke-Git $repo @('add', '.gitignore', 'App.csproj', 'src')
    Invoke-Git $repo @('add', '-f', 'publish/keep.txt')
    Invoke-Git $repo @('commit', '--quiet', '-m', 'fixture')

    # Untracked outputs.
    New-TextFile (Join-Path $repo 'bin\Debug\app.dll') ('a' * 2048)
    New-TextFile (Join-Path $repo 'src\obj\cache.bin') ('b' * 1024)
    New-TextFile (Join-Path $repo 'artifacts\package.nupkg') 'not ignored'
    New-TextFile (Join-Path $repo 'node_modules\left\index.js') 'Node is not used here'
    New-TextFile (Join-Path $repo 'publish\extra.txt') 'untracked beside a tracked file'
    New-TextFile (Join-Path $outside 'precious.txt') 'must survive'
    $null = New-Item -ItemType Junction -Path (Join-Path $repo 'bin\link') -Target $outside

    # Pure functions.
    $languages = @(Get-PresentLanguages -RepositoryRoot $repo)
    Assert-Equal '.NET' (($languages | ForEach-Object Name) -join ',') 'only the languages with a tracked marker are present'

    $candidates = @(Get-BuildOutputCandidates -RepositoryRoot $repo -Languages $languages)
    $relative = @($candidates | ForEach-Object RelativePath)
    Assert-Equal 'artifacts,bin,publish,src/obj' ($relative -join ',') 'candidates are the known output folders of the present languages, nested ones included'
    Assert-True ($relative -notcontains 'node_modules') 'the output folders of an absent language are not candidates'
    Assert-True (@($relative | Where-Object { $_ -like 'bin/*' }).Count -eq 0) 'a matched folder is not walked into'

    $locks = @{}
    foreach ($candidate in $candidates) { $locks[$candidate.RelativePath] = Test-BuildOutputLocks -RepositoryRoot $repo -Path $candidate.Path }
    Assert-True $locks['bin'].Passed 'an ignored untracked output passes the three locks'
    Assert-True $locks['src/obj'].Passed 'a nested ignored output passes the three locks'
    Assert-True ($locks['artifacts'].KnownOutput -and -not $locks['artifacts'].GitIgnored) 'a folder git does not ignore fails the ignore lock'
    Assert-True (-not $locks['artifacts'].Passed) 'a folder git does not ignore is not removable'
    Assert-True ($locks['publish'].KnownOutput -and $locks['publish'].GitIgnored -and -not $locks['publish'].NoTrackedFile) 'an ignored folder holding a tracked file fails the tracked lock'
    $unknown = Test-BuildOutputLocks -RepositoryRoot $repo -Path (Join-Path $repo 'src') -Languages $languages
    Assert-True (-not $unknown.KnownOutput -and -not $unknown.Passed) 'a folder that is no known output fails the known-output lock'
    $escaped = Test-BuildOutputLocks -RepositoryRoot $repo -Path $outside -Languages $languages
    Assert-True (-not $escaped.Passed) 'a path outside the repository never passes'

    Assert-Equal '2.0 KB' (Format-BuildOutputSize -Bytes 2048) 'sizes use KB'
    Assert-Equal '12 B' (Format-BuildOutputSize -Bytes 12) 'small sizes use bytes'

    # Preview changes nothing.
    $preview = @(& pwsh -NoProfile -File $CleanPath -Target $repo 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'the preview succeeds'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'bin\Debug\app.dll')) 'the preview removes nothing'
    Assert-True ($preview -match 'bin\s+2\.0 KB\s+\[passes the three locks\]') 'the preview lists a removable folder with its size'
    Assert-True ($preview -match 'artifacts.*git does not ignore it') 'the preview names the lock a kept folder fails'
    Assert-True ($preview -match 'publish.*it holds a tracked file') 'the preview names the tracked file lock'
    Assert-True ($preview -match 'Would remove\s*:\s*2') 'the preview counts what it would remove'
    Assert-True ($preview -match 'Kept\s*:\s*2') 'the summary counts the kept folders'

    # Apply removes only what passes the locks.
    $applied = @(& pwsh -NoProfile -File $CleanPath -Target $repo -Apply 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'the clean succeeds'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo 'bin'))) 'an ignored output is removed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo 'src\obj'))) 'a nested ignored output is removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'artifacts\package.nupkg')) 'an output git does not ignore is kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'publish\keep.txt')) 'a tracked file survives'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'publish\extra.txt')) 'a folder holding a tracked file is kept whole'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'node_modules\left\index.js')) 'the output of an absent language is left alone'
    Assert-True (Test-Path -LiteralPath (Join-Path $outside 'precious.txt')) 'a link inside an output is not followed'
    Assert-True ($applied -match 'Removed\s*:\s*2') 'the summary counts the removed folders'
    Assert-True ($applied -match 'Freed\s*:\s*3\.0 KB') 'the summary counts the freed bytes'

    # A second run has nothing left to remove.
    $again = @(& pwsh -NoProfile -File $CleanPath -Target $repo -Apply 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'cleaning twice succeeds'
    Assert-True ($again -match 'Removed\s*:\s*0') 'the second run removes nothing'

    # Outside a git repository the script fails with a non-zero code.
    $failed = @(& pwsh -NoProfile -File $CleanPath -Target $plain 2>&1 6>&1) -join "`n"
    Assert-True ($LASTEXITCODE -ne 0) 'a target that is not a git repository fails'
    Assert-True ($failed -match 'Failed') 'the failure is summarized'

    Write-Host 'clean.tests.ps1: PASS' -ForegroundColor Green
} finally {
    $junction = Join-Path $repo 'bin\link'
    if (Test-Path -LiteralPath $junction) { (Get-Item -LiteralPath $junction -Force).Delete() }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
