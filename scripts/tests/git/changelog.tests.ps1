$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScriptPath = Join-Path $ScriptsDir 'git\changelog.ps1'
$EmDash = [string][char]0x2014

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-Matches([string]$Text, [string]$Pattern, [string]$Case) {
    if ($Text -cnotmatch $Pattern) { throw "${Case}: pattern '$Pattern' not found in:`n$Text" }
}

function Assert-NotMatches([string]$Text, [string]$Pattern, [string]$Case) {
    if ($Text -cmatch $Pattern) { throw "${Case}: pattern '$Pattern' unexpectedly found in:`n$Text" }
}

function Invoke-Script([string[]]$Arguments) {
    $text = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1 6>&1) -join "`n"
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
}

function New-Repo([string]$Path) {
    $null = New-Item -ItemType Directory -Path $Path
    & git -C $Path init --quiet
    & git -C $Path config user.name Test
    & git -C $Path config user.email test@example.invalid
}

function Add-Commit([string]$Repo, [string]$Subject, [string]$Body) {
    $arguments = @('-C', $Repo, 'commit', '--quiet', '--allow-empty', '-m', $Subject)
    if ($Body) { $arguments += @('-m', $Body) }
    & git @arguments
    if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
}

function Add-Tag([string]$Repo, [string]$Name) {
    & git -C $Repo tag -a $Name -m $Name
    if ($LASTEXITCODE -ne 0) { throw 'fixture tag failed' }
}

# The part of a document under one heading, up to the next section.
function Get-Section([string]$Text, [string]$HeadingPattern) {
    $lines = $Text -split "`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch $HeadingPattern) { $start = $i; break }
    }
    if ($start -lt 0) { throw "section '$HeadingPattern' not found in:`n$Text" }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^## ') { $end = $i; break }
    }
    return ($lines[$start..($end - 1)] -join "`n")
}

$root = Join-Path ([IO.Path]::GetTempPath()) "changelog-$([guid]::NewGuid())"
try {
    # Release tags decide the sections; version tags past the last release are
    # unreleased work.
    $repo = Join-Path $root 'sample-project'
    New-Repo $repo
    Add-Commit $repo 'feat: add parser'
    Add-Commit $repo 'fix(core): handle empty input'
    Add-Commit $repo 'chore: bump dependencies'
    Add-Commit $repo 'docs: explain the parser'
    Add-Tag $repo 'v0.1.0'
    Add-Tag $repo 'release/v0.1.0'
    Add-Commit $repo 'feat!: drop the legacy flag'
    Add-Commit $repo 'feat: add exporter'
    Add-Tag $repo 'v0.2.0'
    Add-Commit $repo 'fix: late fix'
    Add-Commit $repo 'Merge branch topic'
    $date = (& git -C $repo log -1 --format=%cs 'release/v0.1.0^{commit}').Trim()
    $changelog = Join-Path $repo 'CHANGELOG.md'

    $preview = Invoke-Script @('-Target', $repo)
    Assert-Equal 0 $preview.Code 'the preview succeeds'
    Assert-True (-not (Test-Path -LiteralPath $changelog)) 'the preview writes no file'
    Assert-Matches $preview.Text '# Changelog' 'the preview prints the document header'
    Assert-Matches $preview.Text 'All notable changes to sample-project are recorded here\.' 'the header names the repository folder'
    Assert-Matches $preview.Text 'do not edit it by hand' 'the header says the file is generated'
    Assert-Matches $preview.Text 'CHANGELOG\.md does not exist and would be created' 'the preview says the file would be created'

    $released = Get-Section $preview.Text '^## \[0\.1\.0\]'
    Assert-Matches $released "^## \[0\.1\.0\] $EmDash $date" 'the heading is plain without a GitHub remote, dated by the tag commit'
    Assert-Matches $released '(?m)^### Added\r?\n\r?\n- Add parser' 'feat lands under Added'
    Assert-Matches $released '(?m)^### Fixed\r?\n\r?\n- \*\*core:\*\* Handle empty input' 'fix lands under Fixed with its scope'
    Assert-NotMatches $released 'dependencies|Explain the parser' 'chore and docs never appear'
    Assert-NotMatches $preview.Text '## \[0\.2\.0\]' 'a version tag past the last release is not a section'

    $unreleased = Get-Section $preview.Text '^## \[Unreleased\]'
    Assert-Matches $unreleased '(?m)^### Removed\r?\n\r?\n- Drop the legacy flag' 'feat! lands under Removed'
    Assert-Matches $unreleased '- Add exporter' 'the commits after the release are unreleased'
    Assert-Matches $unreleased '- Late fix' 'the latest commits are unreleased'
    Assert-NotMatches $unreleased 'Merge branch' 'a merge subject never appears'
    Assert-True ($preview.Text.IndexOf('## [Unreleased]') -lt $preview.Text.IndexOf('## [0.1.0]')) 'Unreleased comes first'

    $applied = Invoke-Script @('-Target', $repo, '-Apply')
    Assert-Equal 0 $applied.Code 'apply succeeds'
    Assert-True (Test-Path -LiteralPath $changelog) 'apply writes CHANGELOG.md'
    $bytes = [IO.File]::ReadAllBytes($changelog)
    Assert-True ($bytes -notcontains 13) 'the file has LF line endings only'
    Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'the file has no byte order mark'
    Assert-Matches ([IO.File]::ReadAllText($changelog)) '## \[0\.1\.0\]' 'the file holds the released section'

    $current = Invoke-Script @('-Target', $repo)
    Assert-Matches $current.Text 'CHANGELOG\.md is already current' 'a second preview sees the file is current'
    Assert-Matches $current.Text 'Changed\s*:\s*no' 'the summary says nothing changed'

    # The notes of one version carry that section alone.
    $notes = Invoke-Script @('-Target', $repo, '-NotesFor', '0.1.0')
    Assert-Equal 0 $notes.Code 'release notes succeed'
    Assert-Matches $notes.Text '## \[0\.1\.0\]' 'the notes hold the requested section'
    Assert-Matches $notes.Text '- Add parser' 'the notes list the version commits'
    Assert-NotMatches $notes.Text '# Changelog|Unreleased|Drop the legacy flag' 'the notes hold no header and no other section'

    # A version nobody published yet is rendered as work in progress.
    $pending = Invoke-Script @('-Target', $repo, '-NotesFor', 'v0.2.0')
    Assert-Equal 0 $pending.Code 'notes of an unpublished version succeed'
    Assert-Matches $pending.Text '- Add exporter' 'the unpublished notes hold the commits since the last release'
    Assert-NotMatches $pending.Text 'Add parser' 'the unpublished notes leave out the published version'

    $badNotes = Invoke-Script @('-Target', $repo, '-NotesFor', 'soon')
    Assert-True ($badNotes.Code -ne 0) 'a malformed version fails'

    # -OutFile moves the destination and still needs -Apply.
    $elsewhere = Join-Path $root 'elsewhere.md'
    $previewOut = Invoke-Script @('-Target', $repo, '-OutFile', $elsewhere)
    Assert-Equal 0 $previewOut.Code 'a preview with -OutFile succeeds'
    Assert-True (-not (Test-Path -LiteralPath $elsewhere)) '-OutFile alone writes nothing'
    $appliedOut = Invoke-Script @('-Target', $repo, '-OutFile', $elsewhere, '-Apply')
    Assert-Equal 0 $appliedOut.Code 'apply with -OutFile succeeds'
    Assert-True (Test-Path -LiteralPath $elsewhere) '-OutFile -Apply writes the destination'

    # GitHub remotes turn headings into links, whatever the URL form.
    Add-Commit $repo 'feat: second release'
    Add-Tag $repo 'v0.3.0'
    Add-Tag $repo 'release/v0.3.0'
    & git -C $repo remote add origin 'https://github.com/owner/repo.git'
    $https = Invoke-Script @('-Target', $repo)
    Assert-Matches $https.Text ([regex]::Escape('## [0.3.0](https://github.com/owner/repo/compare/release/v0.1.0...release/v0.3.0)')) 'a heading links to the comparison with the previous release'
    Assert-Matches $https.Text ([regex]::Escape('## [0.1.0](https://github.com/owner/repo/releases/tag/release/v0.1.0)')) 'the first heading links to its tag'
    & git -C $repo remote set-url origin 'git@github.com:owner/repo.git'
    $ssh = Invoke-Script @('-Target', $repo)
    Assert-Matches $ssh.Text ([regex]::Escape('(https://github.com/owner/repo/compare/')) 'an SSH remote links the same way'
    & git -C $repo remote set-url origin 'https://example.invalid/owner/repo.git'
    $other = Invoke-Script @('-Target', $repo)
    Assert-NotMatches $other.Text 'compare/' 'another host gets plain headings'

    # Without a release tag, the version tags are the boundaries.
    $versions = Join-Path $root 'versions-only'
    New-Repo $versions
    Add-Commit $versions 'feat: one'
    Add-Tag $versions 'v0.1.0'
    Add-Commit $versions 'feat: two'
    Add-Tag $versions 'v0.2.0'
    Add-Commit $versions 'fix: three'
    $byVersions = Invoke-Script @('-Target', $versions)
    Assert-Equal 0 $byVersions.Code 'version tags can cut the sections'
    Assert-Matches $byVersions.Text 'version tags \(2\)' 'the summary says which tags cut the sections'
    Assert-True ($byVersions.Text.IndexOf('## [0.2.0]') -lt $byVersions.Text.IndexOf('## [0.1.0]')) 'versions sort descending'
    Assert-Matches (Get-Section $byVersions.Text '^## \[Unreleased\]') '- Three' 'the commits after the last version are unreleased'
    $floored = Invoke-Script @('-Target', $versions, '-Floor', '0.2.0')
    Assert-Matches $floored.Text '## \[0\.2\.0\]' 'the floor keeps its own version'
    Assert-NotMatches $floored.Text '## \[0\.1\.0\]' 'the floor drops older versions'
    Assert-Matches (Get-Section $floored.Text '^## \[0\.2\.0\]') '- Two' 'the first rendered section keeps its range'

    # A repository without any tag is all Unreleased, and does not fail.
    $untagged = Join-Path $root 'untagged'
    New-Repo $untagged
    Add-Commit $untagged 'feat: only commit'
    $none = Invoke-Script @('-Target', $untagged)
    Assert-Equal 0 $none.Code 'a repository without tags does not fail'
    Assert-Matches $none.Text '## \[Unreleased\]' 'everything is unreleased'
    Assert-Matches $none.Text '- Only commit' 'the commit is listed'

    # A revert of a commit of the same range cancels both lines; one that
    # points outside the range stays a Removed.
    $reverts = Join-Path $root 'reverts'
    New-Repo $reverts
    Add-Commit $reverts 'feat: kept'
    Add-Tag $reverts 'v0.1.0'
    Add-Tag $reverts 'release/v0.1.0'
    Add-Commit $reverts 'feat: undone before release'
    $undone = (& git -C $reverts rev-parse HEAD).Trim()
    Add-Commit $reverts 'revert: undone before release' "This reverts commit $undone."
    Add-Commit $reverts 'feat: seen by users'
    $seen = (& git -C $reverts rev-parse HEAD).Trim()
    Add-Tag $reverts 'v0.2.0'
    Add-Tag $reverts 'release/v0.2.0'
    Add-Commit $reverts 'revert: seen by users' "This reverts commit $seen."
    $reverted = Invoke-Script @('-Target', $reverts)
    Assert-Equal 0 $reverted.Code 'reverts are settled'
    Assert-NotMatches $reverted.Text 'Undone before release' 'a revert inside its range cancels both lines'
    Assert-Matches (Get-Section $reverted.Text '^## \[Unreleased\]') '(?m)^### Removed\r?\n\r?\n- Seen by users' 'a revert of a published commit is a Removed'

    Write-Host 'changelog.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
