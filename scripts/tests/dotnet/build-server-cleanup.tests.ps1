$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LibDir = Join-Path $ScriptsDir 'lib'
. (Join-Path $LibDir 'build-server-cleanup.ps1')
Import-Module (Join-Path $LibDir 'script-discovery.psm1') -Force

# Nothing here calls Stop-DotnetBuildServers: it would shut down the build
# servers of every build running on the machine.

function Assert-Equal($Expected, $Actual, [string]$Case) {
    if ($Expected -ne $Actual) { throw "${Case}: expected '$Expected', got '$Actual'" }
}

function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "${Case}: condition was false" }
}

# Sizes.
Assert-Equal '0 B' (Format-ByteSize 0) 'zero bytes'
Assert-Equal '1023 B' (Format-ByteSize 1023) 'bytes stay bytes below 1 KB'
Assert-Equal '1.0 KB' (Format-ByteSize 1KB) 'kilobytes'
Assert-Equal '1.5 MB' (Format-ByteSize (1.5MB)) 'megabytes'
Assert-Equal '2.0 GB' (Format-ByteSize 2GB) 'gigabytes'

# Which processes are build servers.
Assert-Equal 'Roslyn' (Get-BuildServerKind -ProcessName 'VBCSCompiler') 'the Roslyn server is known by its name'
Assert-Equal 'MSBuild' (Get-BuildServerKind -ProcessName 'dotnet' -CommandLine 'dotnet C:\sdk\MSBuild.dll /nodemode:1 /nodeReuse:true') 'an MSBuild node is known by its command line'
Assert-Equal 'MSBuild' (Get-BuildServerKind -ProcessName 'dotnet' -CommandLine '"dotnet.exe" worker /nodemode:1') 'the node mode alone marks an MSBuild node'
Assert-Equal $null (Get-BuildServerKind -ProcessName 'dotnet' -CommandLine 'dotnet run --project App.csproj') 'a dotnet process running an application is not a build server'
Assert-Equal $null (Get-BuildServerKind -ProcessName 'dotnet' -CommandLine '') 'a dotnet process without a command line is never guessed'
Assert-Equal $null (Get-BuildServerKind -ProcessName 'notepad' -CommandLine 'MSBuild.dll') 'other processes are never build servers'

# Reading the machine is safe; stopping it is not tested.
foreach ($process in @(Get-DotnetBuildServerProcesses)) {
    Assert-True ($process.Kind -in @('Roslyn', 'MSBuild')) 'every listed process has a build server kind'
}

# Summaries.
Assert-Equal 'None' (Format-DotnetBuildServerCount -Count 0 -WorkingSet 0) 'no process is None'
Assert-Equal '2 process(es), 3.0 MB' (Format-DotnetBuildServerCount -Count 2 -WorkingSet 3MB) 'a count carries its memory'
Assert-Equal 'None' (Format-DotnetBuildServerList -Processes @()) 'an empty list is None'
$processes = 1..10 | ForEach-Object {
    [pscustomobject]@{ Id = $_; Name = 'dotnet'; Kind = 'MSBuild'; WorkingSet = [int64]1MB }
}
$list = Format-DotnetBuildServerList -Processes $processes
Assert-True ($list.StartsWith('dotnet#1 (MSBuild, 1.0 MB), dotnet#2')) 'the list names each process'
Assert-True ($list.EndsWith('+ 2 more')) 'the list cuts at the limit and counts the rest'
Assert-Equal 'dotnet#1 (MSBuild, 1.0 MB)' (Format-DotnetBuildServerList -Processes @($processes[0])) 'one process is listed alone'

# The script is described in the menu, as a danger action with its sentence.
$header = Read-ScriptHeader -Path (Join-Path $ScriptsDir 'dotnet\stop-build-servers.ps1')
Assert-Equal 'Described' $header.Status 'the stop script has a valid Header'
Assert-Equal '.NET' $header.Section 'the stop script sits in the .NET section'
Assert-Equal 1 @($header.Actions).Count 'the stop script declares one action'
Assert-True $header.Actions[0].Danger 'stopping build servers is a danger action'
Assert-True (-not [string]::IsNullOrWhiteSpace($header.Actions[0].Confirmation)) 'the danger action names what it does'

Write-Host 'build-server-cleanup.tests.ps1: PASS' -ForegroundColor Green
