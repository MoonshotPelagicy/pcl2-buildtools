[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PclRoot
)

$ErrorActionPreference = 'Stop'

$helpRoot = Join-Path $env:RUNNER_TEMP 'PCL2Help'
$helpZip = Join-Path $env:RUNNER_TEMP 'Help.zip'
$resourcesRoot = Join-Path (Join-Path $PclRoot 'Plain Craft Launcher 2') 'Resources'
$destination = Join-Path $resourcesRoot 'Help.zip'

Remove-Item -LiteralPath $helpRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $helpZip -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $resourcesRoot -Force | Out-Null

git clone --depth 1 --branch master https://github.com/LTCatt/PCL2Help.git $helpRoot

# PCL2Help contains repository metadata and root-level helper files. The
# launcher only needs the documentation files inside Help.zip.
Get-ChildItem -LiteralPath $helpRoot -Force -File | Remove-Item -Force
$gitDirectory = Join-Path $helpRoot '.git'
if (Test-Path -LiteralPath $gitDirectory) {
    Remove-Item -LiteralPath $gitDirectory -Recurse -Force
}

Compress-Archive -Path (Join-Path $helpRoot '*') -DestinationPath $helpZip -CompressionLevel Optimal
Copy-Item -LiteralPath $helpZip -Destination $destination -Force

Write-Host "Updated embedded help archive: $destination"
