[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PclRoot,

    [Parameter(Mandatory = $true)]
    [string]$CommitHash
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:PCL_MS_CLIENT_ID)) {
    throw 'The CLIENT_ID repository secret is empty or missing.'
}
if ([string]::IsNullOrWhiteSpace($env:PCL_CURSEFORGE_API_KEY)) {
    throw 'The CURSEFORGE_API_KEY repository secret is empty or missing.'
}
if ([string]::IsNullOrWhiteSpace($CommitHash)) {
    throw 'The upstream commit hash is empty.'
}

$sourceRoot = Join-Path $PclRoot 'Plain Craft Launcher 2'
$modSecretPath = Join-Path (Join-Path $sourceRoot 'Modules') 'ModSecret.vb'
$modBasePath = Join-Path (Join-Path $sourceRoot 'Modules') 'Base\ModBase.vb'

if (-not (Test-Path -LiteralPath $modSecretPath -PathType Leaf)) {
    throw "Patch target does not exist: $modSecretPath"
}
if (-not (Test-Path -LiteralPath $modBasePath -PathType Leaf)) {
    throw "Build metadata target does not exist: $modBasePath"
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-ExactOccurrenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )

    $count = 0
    $start = 0
    while ($true) {
        $index = $Text.IndexOf($Needle, $start, [System.StringComparison]::Ordinal)
        if ($index -lt 0) {
            break
        }
        $count++
        $start = $index + $Needle.Length
    }
    return $count
}

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $count = Get-ExactOccurrenceCount -Text $Text -Needle $Old
    if ($count -ne 1) {
        throw "Patch target '$Description' must occur exactly once; found $count occurrence(s)."
    }
    return $Text.Replace($Old, $New)
}

function ConvertTo-VbStringContent {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($Value.Contains("`r") -or $Value.Contains("`n")) {
        throw "$Description contains a line break and cannot be embedded in VB source."
    }
    return $Value.Replace('"', '""')
}

$clientId = ConvertTo-VbStringContent -Value $env:PCL_MS_CLIENT_ID -Description 'CLIENT_ID'
$curseForgeKey = ConvertTo-VbStringContent -Value $env:PCL_CURSEFORGE_API_KEY -Description 'CURSEFORGE_API_KEY'
$commit = ConvertTo-VbStringContent -Value $CommitHash -Description 'upstream commit hash'

$modSecret = [System.IO.File]::ReadAllText($modSecretPath, $utf8NoBom)
$modSecret = Replace-ExactOnce `
    -Text $modSecret `
    -Old 'Public Const RestrictMcDownload As Boolean = True' `
    -New 'Public Const RestrictMcDownload As Boolean = False' `
    -Description 'RestrictMcDownload'

$modSecret = Replace-ExactOnce `
    -Text $modSecret `
    -Old 'Public OAuthClientId As String = If(Environment.GetEnvironmentVariable("PCL_MS_CLIENT_ID"), "")' `
    -New ('Public OAuthClientId As String = If(Environment.GetEnvironmentVariable("PCL_MS_CLIENT_ID"), "' + $clientId + '")') `
    -Description 'OAuthClientId fallback'

$modSecret = Replace-ExactOnce `
    -Text $modSecret `
    -Old 'Public CurseForgeAPIKey As String = If(Environment.GetEnvironmentVariable("PCL_CURSEFORGE_API_KEY"), "")' `
    -New ('Public CurseForgeAPIKey As String = If(Environment.GetEnvironmentVariable("PCL_CURSEFORGE_API_KEY"), "' + $curseForgeKey + '")') `
    -Description 'CurseForgeAPIKey fallback'

$modBase = [System.IO.File]::ReadAllText($modBasePath, $utf8NoBom)
$modBase = Replace-ExactOnce `
    -Text $modBase `
    -Old 'Public Const CommitHash As String = ""' `
    -New ('Public Const CommitHash As String = "' + $commit + '"') `
    -Description 'CommitHash'

[System.IO.File]::WriteAllText($modSecretPath, $modSecret, $utf8NoBom)
[System.IO.File]::WriteAllText($modBasePath, $modBase, $utf8NoBom)

Write-Host 'Applied source patch: RestrictMcDownload = False.'
Write-Host 'Injected build-time fallbacks for OAuthClientId and CurseForgeAPIKey.'
Write-Host "Recorded upstream commit: $CommitHash"
