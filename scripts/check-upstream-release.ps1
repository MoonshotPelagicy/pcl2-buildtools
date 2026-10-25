[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UpstreamRepository,

    [Parameter(Mandatory = $true)]
    [string]$DownstreamRepository,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    throw 'GITHUB_OUTPUT is not available.'
}

$headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'pcl2-buildtools'
}
if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    $headers.Authorization = "Bearer $($env:GH_TOKEN)"
}

function Get-GitHubJson {
    param([Parameter(Mandatory = $true)][string]$Uri)
    Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
}

$upstream = Get-GitHubJson "https://api.github.com/repos/$UpstreamRepository/releases/latest"
$upstreamTag = [string]$upstream.tag_name
if ([string]::IsNullOrWhiteSpace($upstreamTag)) {
    throw "The upstream repository has no stable latest Release: $UpstreamRepository"
}

$downstream = $null
try {
    $downstream = Get-GitHubJson "https://api.github.com/repos/$DownstreamRepository/releases/latest"
}
catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -ne 404) {
        throw
    }
}

# Every release created by this workflow has this tag. Comparing against the
# downstream latest Release avoids creating a second Release for one upstream tag.
$releaseTag = "pcl-$upstreamTag-patched"
$shouldBuild = $Force -or $null -eq $downstream -or [string]$downstream.tag_name -ne $releaseTag

Write-Host "Upstream latest Release: $upstreamTag"
if ($null -eq $downstream) {
    Write-Host 'Downstream latest Release: none'
}
else {
    Write-Host "Downstream latest Release: $($downstream.tag_name)"
}
Write-Host "Build required: $shouldBuild"

@(
    "should_build=$($shouldBuild.ToString().ToLowerInvariant())"
    "upstream_tag=$upstreamTag"
    "upstream_release_url=$([string]$upstream.html_url)"
    "release_tag=$releaseTag"
) | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
