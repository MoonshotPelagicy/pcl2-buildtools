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

# The upstream repository can publish its stable ZIP without a GitHub Release
# or tag. Use the latest change to that file on the default branch instead.
$packagePath = [Uri]::EscapeDataString('最新正式版.zip')
$upstreamCommits = @(Get-GitHubJson "https://api.github.com/repos/$UpstreamRepository/commits?path=$packagePath&per_page=1")
if ($upstreamCommits.Count -eq 0) {
    throw "No upstream commit found for 最新正式版.zip: $UpstreamRepository"
}
$upstreamCommit = [string]$upstreamCommits[0].sha
if ($upstreamCommit -notmatch '\A[0-9a-f]{40}\z') {
    throw "Invalid upstream commit SHA: $upstreamCommit"
}
$upstreamCommitUrl = "https://github.com/$UpstreamRepository/commit/$upstreamCommit"

# Read the version from the exact commit that will be built, not from a moving
# branch or from the commit message.
$sourcePath = 'Plain%20Craft%20Launcher%202/Modules/Base/ModBase.vb'
$source = Get-GitHubJson "https://api.github.com/repos/$UpstreamRepository/contents/${sourcePath}?ref=$upstreamCommit"
if ($source.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace([string]$source.content)) {
    throw 'The upstream version source has no base64 content.'
}
$sourceText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($source.content))
$versionMatches = [regex]::Matches($sourceText, '(?im)^\s*Public\s+Const\s+VersionBaseName\s+As\s+String\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"')
if ($versionMatches.Count -ne 1) {
    throw 'Expected exactly one upstream VersionBaseName with a four-part version.'
}
$upstreamVersion = $versionMatches[0].Groups[1].Value
$null = [version]::Parse($upstreamVersion)

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

# Only a successfully published build records this marker. A legacy Release
# without a marker is rebuilt once; a failed build will be retried next time.
$downstreamCommit = ''
if ($null -ne $downstream) {
    $commitMatch = [regex]::Match([string]$downstream.body, '(?im)^Upstream commit: ([0-9a-f]{40})\r?$')
    if ($commitMatch.Success) {
        $downstreamCommit = $commitMatch.Groups[1].Value
    }
}
$releaseTag = "pcl-$upstreamVersion-patched"
$shouldBuild = $Force -or $null -eq $downstream -or [string]$downstream.tag_name -ne $releaseTag -or $downstreamCommit -ne $upstreamCommit

Write-Host "Upstream stable version: $upstreamVersion"
Write-Host "Upstream package commit: $upstreamCommit"
if ($null -eq $downstream) {
    Write-Host 'Downstream latest Release: none'
}
else {
    Write-Host "Downstream latest Release: $($downstream.tag_name)"
    Write-Host "Downstream recorded upstream commit: $downstreamCommit"
}
Write-Host "Build required: $shouldBuild"

@(
    "should_build=$($shouldBuild.ToString().ToLowerInvariant())"
    "upstream_version=$upstreamVersion"
    "upstream_commit=$upstreamCommit"
    "upstream_commit_url=$upstreamCommitUrl"
    "release_tag=$releaseTag"
) | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
