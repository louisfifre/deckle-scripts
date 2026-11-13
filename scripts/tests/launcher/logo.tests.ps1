$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $ScriptsDir 'lib\launcher\logo.ps1')

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

$logo = @(ConvertTo-LauncherLogo -Text 'homelab')
Assert-Equal 2 $logo.Count 'a name is drawn on two lines'
Assert-Equal '█ █ █▀█ █▀▄▀█ █▀▀ █   ▄▀█ █▄▄' $logo[0] 'the top line of a lowercase name, in capitals'
Assert-Equal '█▀█ █▄█ █ ▀ █ ██▄ █▄▄ █▀█ █▄█' $logo[1] 'the bottom line of a lowercase name, in capitals'

$dashed = @(ConvertTo-LauncherLogo -Text 'deckle-scripts')
Assert-Equal 2 $dashed.Count 'a dash belongs to the font'

Assert-Equal 0 @(ConvertTo-LauncherLogo -Text 'café').Count 'a character outside the font leaves the logo out'
Assert-Equal 0 @(ConvertTo-LauncherLogo -Text '').Count 'an empty name draws no logo'

$menuPath = Join-Path $ScriptsDir 'menu.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "logo-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'scripts')
    & git -C $root init -q
    $menu = @(& pwsh -NoProfile -File $menuPath -Snapshot Menu -ScriptsRoot (Join-Path $root 'scripts')) -join "`n"
    $expected = @(ConvertTo-LauncherLogo -Text (Split-Path -Leaf $root))
    Assert-Equal $true ($menu.Contains($expected[0]) -and $menu.Contains($expected[1])) 'the Menu opens with the repository name as its logo'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

'PASS'
