$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fixture.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/manifest.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) "update-$([guid]::NewGuid())"
try {
    $source = Join-Path $root 'source'
    $target = Join-Path $root 'target'
    New-SourceFixture $source
    New-TargetFixture $target
    $sourceUpdate = Join-Path $source 'scripts/update.ps1'
    $manifestPath = Join-Path $target 'scripts/.deckle-scripts/manifest.json'

    # Preview prints the plan and creates nothing.
    $preview = Invoke-Script $sourceUpdate @('-Target', $target)
    Assert-Equal 0 $preview.ExitCode 'a preview succeeds'
    Assert-True ($preview.Text -match 'Add \(\d+\)') 'the preview lists the files to add'
    foreach ($path in @('scripts/menu.ps1', 'scripts/update.ps1', 'scripts/lib/sample.ps1', 'scripts/alpha/one.ps1', 'scripts/beta/two.ps1')) {
        Assert-True ($preview.Text -match [regex]::Escape($path)) "the preview names $path"
    }
    Assert-True ($preview.Text -notmatch 'scripts/tests') 'the tests are never part of the plan'
    Assert-True ($preview.Text -match 'not installed') 'the preview says nothing is installed yet'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'scripts'))) 'a preview creates nothing'

    # Apply installs the owned files and writes the manifest.
    $apply = Invoke-Script $sourceUpdate @('-Target', $target, '-Apply')
    Assert-Equal 0 $apply.ExitCode 'an apply succeeds'
    foreach ($path in @('scripts/menu.ps1', 'scripts/update.ps1', 'scripts/lib/version.ps1', 'scripts/lib/sample.ps1', 'scripts/alpha/one.ps1', 'scripts/beta/two.ps1')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $target $path)) "$path is installed"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'scripts/tests'))) 'scripts/tests is never installed'
    $manifest = Read-InstallManifest -RepositoryRoot $target
    Assert-Equal '0.1.0' $manifest.version 'the manifest records the version'
    Assert-Equal 'alpha,beta' (@($manifest.packs) -join ',') 'the manifest records every pack'
    Assert-Equal $source ([string]$manifest.source) 'the manifest records the source'
    $files = Get-InstallManifestFiles -Manifest $manifest
    Assert-Equal (Get-ContentFingerprint -Path (Join-Path $source 'scripts/lib/sample.ps1')) $files['scripts/lib/sample.ps1'] 'the manifest holds the fingerprint of an installed file'
    Assert-True (-not $files.Contains('scripts/tests/t.tests.ps1')) 'the manifest does not list the tests'
    Assert-True (-not $files.Contains('scripts/.deckle-scripts/manifest.json')) 'the manifest does not list itself'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $source 'scripts/.deckle-scripts'))) 'the source gets no manifest'

    # A second apply has nothing to do.
    $again = Invoke-Script $sourceUpdate @('-Target', $target, '-Apply')
    Assert-Equal 0 $again.ExitCode 'a second apply succeeds'
    Assert-True ($again.Text -match 'already up to date') 'a second apply says up to date'
    Assert-True ($again.Text -match 'Skipped') 'a second apply is Skipped'

    # -Packs limits a fresh install.
    $alphaTarget = Join-Path $root 'alpha-target'
    New-TargetFixture $alphaTarget
    $alpha = Invoke-Script $sourceUpdate @('-Target', $alphaTarget, '-Packs', 'alpha', '-Apply')
    Assert-Equal 0 $alpha.ExitCode 'installing one pack succeeds'
    Assert-True (Test-Path -LiteralPath (Join-Path $alphaTarget 'scripts/alpha/one.ps1')) 'the chosen pack is installed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $alphaTarget 'scripts/beta'))) 'a pack that was not chosen is not installed'
    Assert-Equal 'alpha' (@((Read-InstallManifest -RepositoryRoot $alphaTarget).packs) -join ',') 'the manifest records the chosen pack only'

    $unknown = Invoke-Script $sourceUpdate @('-Target', $alphaTarget, '-Packs', 'nope')
    Assert-True ($unknown.ExitCode -ne 0) 'an unknown pack fails'
    Assert-True ($unknown.Text -match 'Unknown pack\(s\): nope') 'the unknown pack is named'
    Assert-True ($unknown.Text -match 'alpha, beta') 'the packs on offer are listed'

    $same = Invoke-Script $sourceUpdate @('-Target', $source)
    Assert-True ($same.ExitCode -ne 0) 'the source cannot update itself'
    Assert-True ($same.Text -match 'same repository') 'the same-repository failure says why'

    # A new version: a changed file and a removed one. The target updates itself.
    Set-FixtureFile $source 'scripts/lib/sample.ps1' "# sample v2`n"
    Remove-Item -LiteralPath (Join-Path $source 'scripts/beta/two.ps1')
    Save-Commit $source 'second'
    Invoke-Git $source @('tag', '-a', 'v0.2.0', '-m', 'Version 0.2.0')
    # Not committed: a tagged install must ignore the working tree.
    Set-FixtureFile $source 'scripts/alpha/stray.ps1' "# stray`n"

    $targetUpdate = Join-Path $target 'scripts/update.ps1'
    $second = Invoke-Script $targetUpdate @('-Version', '0.2.0')
    Assert-Equal 0 $second.ExitCode 'the installed update previews'
    Assert-True ($second.Text -match 'Update \(1\)') 'the preview lists the changed file'
    Assert-True ($second.Text -match 'Remove \(1\)') 'the preview lists the removed file'
    Assert-True ($second.Text -match '0\.1\.0 -> 0\.2\.0') 'the preview shows the version change'
    Assert-True ((Get-Content -LiteralPath (Join-Path $target 'scripts/lib/sample.ps1') -Raw) -match 'v1') 'the preview changes nothing'
    Assert-True (Test-Path -LiteralPath (Join-Path $target 'scripts/beta/two.ps1')) 'the preview removes nothing'

    $secondApply = Invoke-Script $targetUpdate @('-Version', '0.2.0', '-Apply')
    Assert-Equal 0 $secondApply.ExitCode 'the installed update applies'
    Assert-True ((Get-Content -LiteralPath (Join-Path $target 'scripts/lib/sample.ps1') -Raw) -match 'v2') 'the changed file is updated'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'scripts/beta'))) 'the removed file and its empty folder are gone'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'scripts/alpha/stray.ps1'))) 'a tagged install ignores the working tree'
    $manifest = Read-InstallManifest -RepositoryRoot $target
    Assert-Equal '0.2.0' $manifest.version 'the manifest records the new version'
    Assert-True (-not (Get-InstallManifestFiles -Manifest $manifest).Contains('scripts/beta/two.ps1')) 'the manifest forgets the removed file'

    # A file edited locally stops the update; -Force overwrites it.
    Remove-Item -LiteralPath (Join-Path $source 'scripts/alpha/stray.ps1')
    $edited = Join-Path $target 'scripts/lib/sample.ps1'
    Add-Content -LiteralPath $edited -Value '# local edit'
    $previewEdited = Invoke-Script $targetUpdate @('-Version', '0.2.0')
    Assert-Equal 0 $previewEdited.ExitCode 'a preview does not fail on a local edit'
    Assert-True ($previewEdited.Text -match 'Modified \(1\)') 'the preview lists the locally edited file'
    Assert-True ($previewEdited.Text -match 'Partial') 'the preview says the update would stop'
    $stopped = Invoke-Script $targetUpdate @('-Version', '0.2.0', '-Apply')
    Assert-Equal 1 $stopped.ExitCode 'a locally edited file stops the update'
    Assert-True ($stopped.Text -match 'Modified \(1\)') 'the stop names the state'
    Assert-True ($stopped.Text -match 'edited locally') 'the stop says why'
    Assert-True ((Get-Content -LiteralPath $edited -Raw) -match 'local edit') 'the stopped update leaves the edit alone'
    $forced = Invoke-Script $targetUpdate @('-Version', '0.2.0', '-Apply', '-Force')
    Assert-Equal 0 $forced.ExitCode '-Force overwrites the edit'
    Assert-True ((Get-Content -LiteralPath $edited -Raw) -notmatch 'local edit') 'the edit is gone after -Force'

    # A file the install does not own is never overwritten, -Force or not.
    $conflictTarget = Join-Path $root 'conflict-target'
    New-TargetFixture $conflictTarget
    Set-FixtureFile $conflictTarget 'scripts/lib/sample.ps1' "# mine`n"
    foreach ($arguments in @(@('-Apply'), @('-Apply', '-Force'))) {
        $conflict = Invoke-Script $sourceUpdate (@('-Target', $conflictTarget) + $arguments)
        Assert-Equal 1 $conflict.ExitCode "a conflict stops the install ($($arguments -join ' '))"
        Assert-True ($conflict.Text -match 'Conflict \(1\)') 'the conflict is listed'
        Assert-True ($conflict.Text -match 'never overwrites') 'the stop says the file is not owned'
        Assert-True ((Get-Content -LiteralPath (Join-Path $conflictTarget 'scripts/lib/sample.ps1') -Raw) -match 'mine') 'the unowned file is untouched'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $conflictTarget 'scripts/menu.ps1'))) 'a stopped install changes nothing'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $conflictTarget 'scripts/.deckle-scripts'))) 'a stopped install writes no manifest'
    }

    # A bare repository is read like a remote: the latest tag wins, a tag can be asked for.
    $bare = Join-Path $root 'bare.git'
    Invoke-Git $source @('clone', '--quiet', '--bare', $source, $bare)
    $latestTarget = Join-Path $root 'latest-target'
    New-TargetFixture $latestTarget
    $latest = Invoke-Script $sourceUpdate @('-Target', $latestTarget, '-Source', $bare, '-Apply')
    Assert-Equal 0 $latest.ExitCode 'a bare source installs'
    $latestManifest = Read-InstallManifest -RepositoryRoot $latestTarget
    Assert-Equal '0.2.0' $latestManifest.version 'without -Version the highest tag is picked'
    Assert-Equal $bare ([string]$latestManifest.source) 'the manifest records the bare source'
    Assert-True ((Get-Content -LiteralPath (Join-Path $latestTarget 'scripts/lib/sample.ps1') -Raw) -match 'v2') 'the highest tag content is installed'

    $oldTarget = Join-Path $root 'old-target'
    New-TargetFixture $oldTarget
    $old = Invoke-Script $sourceUpdate @('-Target', $oldTarget, '-Source', $bare, '-Version', 'v0.1.0', '-Apply')
    Assert-Equal 0 $old.ExitCode 'a bare source installs an older tag'
    Assert-Equal '0.1.0' (Read-InstallManifest -RepositoryRoot $oldTarget).version 'the asked version is installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $oldTarget 'scripts/beta/two.ps1')) 'the older tag still holds the removed file'

    $missing = Invoke-Script $sourceUpdate @('-Target', $oldTarget, '-Source', $bare, '-Version', '9.9.9')
    Assert-True ($missing.ExitCode -ne 0) 'a version the source does not have fails'
    Assert-True ($missing.Text -match 'has no tag v9\.9\.9') 'the missing tag is named'

    Write-Host 'update.tests.ps1: PASS' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
