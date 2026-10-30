$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fixture.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/manifest.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) "manifest-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory -Path $root
try {
    # The fingerprint ignores the line endings a checkout may change.
    $lf = Join-Path $root 'lf.txt'
    $crlf = Join-Path $root 'crlf.txt'
    $other = Join-Path $root 'other.txt'
    [IO.File]::WriteAllBytes($lf, [Text.Encoding]::UTF8.GetBytes("one`ntwo`n"))
    [IO.File]::WriteAllBytes($crlf, [Text.Encoding]::UTF8.GetBytes("one`r`ntwo`r`n"))
    [IO.File]::WriteAllBytes($other, [Text.Encoding]::UTF8.GetBytes("one`ntwo!`n"))
    Assert-Equal (Get-ContentFingerprint -Path $lf) (Get-ContentFingerprint -Path $crlf) 'CRLF and LF variants share a fingerprint'
    Assert-True ((Get-ContentFingerprint -Path $lf) -ne (Get-ContentFingerprint -Path $other)) 'different content has a different fingerprint'

    $abc = Join-Path $root 'abc.txt'
    [IO.File]::WriteAllBytes($abc, [Text.Encoding]::ASCII.GetBytes('abc'))
    Assert-Equal 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' (Get-ContentFingerprint -Path $abc) 'the fingerprint is the lowercase SHA-256 hex'

    # A repository without a manifest reads as not installed.
    $repository = Join-Path $root 'repository'
    $null = New-Item -ItemType Directory -Path $repository
    Assert-Equal $null (Read-InstallManifest -RepositoryRoot $repository) 'an absent manifest reads as null'
    $path = Get-InstallManifestPath -RepositoryRoot $repository
    Assert-True ($path.Replace('\', '/').EndsWith('/scripts/.deckle-scripts/manifest.json')) 'the manifest sits under scripts/.deckle-scripts'

    # Write then read keeps the content and sorts the paths.
    Write-InstallManifest -RepositoryRoot $repository -Manifest ([pscustomobject]@{
        source      = 'https://example.invalid/x.git'
        version     = '1.2.3'
        packs       = @('setup', 'git')
        installedAt = '2026-10-30T10:00:00Z'
        files       = @{ 'scripts/menu.ps1' = 'bb'; 'scripts/lib/a.ps1' = 'aa'; 'Scripts/Z.ps1' = 'cc' }
    })
    $manifest = Read-InstallManifest -RepositoryRoot $repository
    Assert-Equal 'https://example.invalid/x.git' $manifest.source 'the source round-trips'
    Assert-Equal '1.2.3' $manifest.version 'the version round-trips'
    Assert-Equal 'git,setup' (@($manifest.packs) -join ',') 'the packs are written sorted'
    Assert-Equal 'Scripts/Z.ps1,scripts/lib/a.ps1,scripts/menu.ps1' (@($manifest.files.PSObject.Properties.Name) -join ',') 'the file paths are sorted by code point'
    Assert-Equal 'aa' (Get-InstallManifestFiles -Manifest $manifest)['scripts/lib/a.ps1'] 'a fingerprint round-trips'
    Assert-Equal '2026' $manifest.installedAt.Year.ToString() 'the timestamp is read back'

    # The bytes are stable: LF, no byte order mark, two-space indentation.
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'the manifest has no byte order mark'
    Assert-True ($bytes -notcontains 13) 'the manifest has LF line endings'
    Assert-Equal 10 $bytes[-1] 'the manifest ends with a newline'
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Assert-True ($text -match '(?m)^  "source": ') 'the manifest is indented by two spaces'
    Assert-True ($text -match '(?m)^    "scripts/lib/a\.ps1": "aa"') 'file entries sit two levels deep'

    # Writing a manifest that was read back keeps it identical.
    $before = [IO.File]::ReadAllText($path)
    Write-InstallManifest -RepositoryRoot $repository -Manifest $manifest
    Assert-Equal $before ([IO.File]::ReadAllText($path)) 'rewriting a read manifest changes nothing'

    # An empty pack list stays a list.
    Write-InstallManifest -RepositoryRoot $repository -Manifest ([pscustomobject]@{
        source = 's'; version = '1.0.0'; packs = @(); installedAt = '2026-10-30T10:00:00Z'; files = @{}
    })
    Assert-True ([IO.File]::ReadAllText($path) -match '"packs": \[\]') 'an empty pack list is written as a list'

    [IO.File]::WriteAllText($path, '{ not json')
    $threw = $false
    try { Read-InstallManifest -RepositoryRoot $repository | Out-Null } catch { $threw = $_.Exception.Message -match 'not valid JSON' }
    Assert-True $threw 'a broken manifest says so'

    Write-Host 'manifest.tests.ps1: PASS' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
