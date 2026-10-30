# Installs Deckle Scripts into the git repository you are in, at the latest version.
#   irm https://raw.githubusercontent.com/louisfifre/deckle-scripts/main/install.ps1 | iex
#   pwsh -File install.ps1
# Windows PowerShell 5.1 may run this file: it stays ASCII, takes no param block
# (iex cannot pass arguments) and uses no PowerShell 7 syntax. The real work is
# scripts/update.ps1, which this file only fetches and starts.

$SourceUrl = 'https://github.com/louisfifre/deckle-scripts.git'

# A block, not top-level code: under iex a bare exit would close the user's shell.
$exitCode = & {
    $ErrorActionPreference = 'Continue'  # 5.1 would stop on git's stderr otherwise; exit codes are checked
    function Say([string]$Text) { Write-Information -MessageData $Text -InformationAction Continue }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Say 'Git is required: install it from https://git-scm.com, then run this again.'; return 1 }
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Say 'PowerShell 7 is required: install it with "winget install Microsoft.PowerShell", then run this again.'; return 1 }

    $target = @(git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $target.Count -eq 0) { Say 'Run this inside the repository to equip: this folder is not in a git repository.'; return 1 }

    $lines = @(git ls-remote --tags $SourceUrl 2>&1)
    if ($LASTEXITCODE -ne 0) { Say "Git could not reach ${SourceUrl}: $($lines -join ' ')"; return 1 }
    $versions = @(foreach ($line in $lines) { if ("$line" -match 'refs/tags/(v\d+\.\d+\.\d+)$') { $Matches[1] } })
    if ($versions.Count -eq 0) { Say "$SourceUrl has no version tag vX.Y.Z."; return 1 }
    $tag = $versions | Sort-Object { [version]$_.Substring(1) } | Select-Object -Last 1

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('deckle-scripts-' + [guid]::NewGuid())
    try {
        $log = @(git clone --quiet --depth 1 --branch $tag $SourceUrl $temp 2>&1)
        if ($LASTEXITCODE -ne 0) { Say "Git could not fetch ${tag}: $($log -join ' ')"; return 1 }
        $update = Join-Path $temp 'scripts\update.ps1'
        # Start-Process keeps the console, so the update prints in color as it runs.
        $arguments = '-NoProfile -File "' + $update + '" -Target "' + $target[0] + '" -Source "' + $SourceUrl + '" -Version ' + $tag + ' -Apply'
        $process = Start-Process -FilePath 'pwsh' -ArgumentList $arguments -NoNewWindow -Wait -PassThru
        return [int]$process.ExitCode
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if ($PSCommandPath) { exit $exitCode } else { $global:LASTEXITCODE = $exitCode }
