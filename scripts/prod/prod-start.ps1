# Starts the prod copy, swapping in the build that waits in next\ first.
#
# This file has no Header on purpose: it is not run from the repository.
# deploy-prod.ps1 copies it to <Root>\start.ps1 for projects whose settings
# say Swap 'start', and the person's shortcut runs that copy:
#   pwsh -NoProfile -File <Root>\start.ps1 [arguments for the app]
# It reads nothing from the repository: everything it needs is in the stamp,
# .prod.json, of the slot it starts. Projects whose app swaps the slots itself
# (Swap 'app') never get it.
#
# The swap happens only while nothing runs from current\: a process whose
# program sits in current\, or whose command line names it. While one runs,
# the start runs current\ as it is and next\ keeps waiting.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$current = Join-Path $root 'current'
$next = Join-Path $root 'next'
$previous = Join-Path $root 'previous'
$stampName = '.prod.json'

function Write-StartLog([string]$Line) {
    Add-Content -LiteralPath (Join-Path $root 'start.log') -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Line"
}

function Read-Stamp([string]$Folder) {
    $path = Join-Path $Folder $stampName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Test-CurrentRunning {
    $prefix = "$current\"
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath, CommandLine)) {
        if ($process.ProcessId -eq $PID) { continue }
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($process.CommandLine -and $process.CommandLine.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

$waiting = Read-Stamp $next
if ($waiting -and -not (Test-CurrentRunning)) {
    $moved = [System.Collections.Generic.List[string]]::new()
    try {
        # The folders that belong to the machine, not to a build, follow the
        # build that runs: its log, its data.
        foreach ($name in @($waiting.carry)) {
            if (-not $name) { continue }
            $from = Join-Path $current $name
            $to = Join-Path $next $name
            if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) { Move-Item -LiteralPath $from -Destination $to; $moved.Add($name) }
        }
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
        if (Test-Path -LiteralPath $current) { Rename-Item -LiteralPath $current -NewName 'previous' }
        Rename-Item -LiteralPath $next -NewName 'current'
        Write-StartLog "swapped in $($waiting.version) $($waiting.commit)"
    } catch {
        # Put back what moved, so the build that ran before still starts.
        if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $previous)) { Rename-Item -LiteralPath $previous -NewName 'current' }
        if (Test-Path -LiteralPath $next) {
            foreach ($name in $moved) { Move-Item -LiteralPath (Join-Path $next $name) -Destination (Join-Path $current $name) -ErrorAction SilentlyContinue }
        }
        Write-StartLog "swap failed, the build in current\ stays: $($_.Exception.Message)"
    }
} elseif ($waiting) {
    Write-StartLog "$($waiting.version) waits in next\: a program runs from current\"
}

$stamp = Read-Stamp $current
if (-not $stamp -or -not $stamp.start) {
    Write-StartLog 'no prod build to start: run scripts\prod\deploy-prod.ps1 in the repository'
    throw "No prod build in $current to start: run scripts\prod\deploy-prod.ps1 in the repository."
}

# The program is named relative to the slot; it starts with an absolute path,
# so its command line names current\ and the next start sees it running.
$program = Join-Path $current $stamp.start
$arguments = @(@($stamp.startArguments) | Where-Object { $null -ne $_ }) + @($args)
Push-Location -LiteralPath $current
try {
    if ($program.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
        & pwsh -NoProfile -File $program @arguments
    } else {
        & $program @arguments
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
