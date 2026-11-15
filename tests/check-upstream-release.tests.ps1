$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot '../scripts/check-upstream-release.ps1'
$packageCommit = '1111111111111111111111111111111111111111'
$previousCommit = '2222222222222222222222222222222222222222'
$packagePath = [Uri]::EscapeDataString('最新正式版.zip')
$commitsUri = "https://api.github.com/repos/test/upstream/commits?path=$packagePath&per_page=1"
$sourceUri = "https://api.github.com/repos/test/upstream/contents/Plain%20Craft%20Launcher%202/Modules/Base/ModBase.vb?ref=$packageCommit"
$downstreamUri = 'https://api.github.com/repos/test/downstream/releases/latest'

# Mock only the HTTP boundary; execute the actual checker for each scenario.
function Invoke-RestMethod {
    param($Uri, $Headers, $Method)

    $requestedUris.Add([string]$Uri)
    if ($Uri -eq $commitsUri) {
        if ($fixture.EmptyHistory) { return @() }
        if ($fixture.InvalidCommit) { return @(@{ sha = 'invalid' }) }
        return @(@{ sha = $packageCommit })
    }
    if ($Uri -eq $sourceUri) {
        $text = 'Public Const VersionBaseName As String = "2.99.0.1"'
        if ($fixture.ContainsKey('SourceText')) { $text = $fixture.SourceText }
        return @{
            encoding = 'base64'
            content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
        }
    }
    if ($Uri -eq $downstreamUri) {
        if ($fixture.HttpStatus) {
            $response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$fixture.HttpStatus)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Fixture HTTP error', $response)
        }
        return @{
            tag_name = $fixture.Tag
            body = $fixture.Body
        }
    }
    throw "Unexpected request (must use the package commit, not upstream Releases or HEAD): $Uri"
}

$cases = @(
    @{ Name = 'unchanged package skips'; Tag = 'pcl-2.99.0.1-patched'; Body = "Upstream commit: $packageCommit"; Build = 'false' }
    @{ Name = 'same version with new package builds'; Tag = 'pcl-2.99.0.1-patched'; Body = "Upstream commit: $previousCommit"; Build = 'true' }
    @{ Name = 'new version builds'; Tag = 'pcl-2.99.0.0-patched'; Body = "Upstream commit: $previousCommit"; Build = 'true' }
    @{ Name = 'legacy Release migrates'; Tag = 'pcl-2.99.0.1-patched'; Body = 'Legacy release notes'; Build = 'true' }
    @{ Name = 'no downstream Release builds'; HttpStatus = 404; Build = 'true' }
    @{ Name = 'force rebuilds unchanged package'; Tag = 'pcl-2.99.0.1-patched'; Body = "Upstream commit: $packageCommit"; Force = $true; Build = 'true' }
    @{ Name = 'CRLF release notes skip'; Tag = 'pcl-2.99.0.1-patched'; Body = "Description`r`n`r`nUpstream commit: $packageCommit`r`n"; Build = 'false' }
    @{ Name = 'forbidden response fails'; HttpStatus = 403; Error = 'Fixture HTTP error' }
    @{ Name = 'server error fails'; HttpStatus = 500; Error = 'Fixture HTTP error' }
    @{ Name = 'missing stable ZIP fails'; EmptyHistory = $true; Error = 'No upstream commit found' }
    @{ Name = 'invalid SHA fails'; InvalidCommit = $true; Error = 'Invalid upstream commit SHA' }
    @{ Name = 'missing version fails'; SourceText = 'Public Module ModBase'; Error = 'Expected exactly one upstream VersionBaseName' }
    @{ Name = 'malformed version fails'; SourceText = 'Public Const VersionBaseName As String = "2.99"'; Error = 'Expected exactly one upstream VersionBaseName' }
    @{ Name = 'ambiguous version fails'; SourceText = "Public Const VersionBaseName As String = `"2.99.0.1`"`nPublic Const VersionBaseName As String = `"2.99.0.2`""; Error = 'Expected exactly one upstream VersionBaseName' }
)

$previousOutput = $env:GITHUB_OUTPUT
try {
    foreach ($case in $cases) {
        $fixture = $case
        $requestedUris = [Collections.Generic.List[string]]::new()
        $env:GITHUB_OUTPUT = [IO.Path]::GetTempFileName()
        try {
            $failure = $null
            try {
                & $checker -UpstreamRepository 'test/upstream' -DownstreamRepository 'test/downstream' -Force:([bool]$case.Force)
            }
            catch {
                $failure = $_
            }
            $outputText = [IO.File]::ReadAllText($env:GITHUB_OUTPUT)
            if ($case.Error) {
                if ($null -eq $failure -or -not $failure.ToString().Contains($case.Error)) {
                    throw "Expected error '$($case.Error)', got '$failure'."
                }
                if ($outputText.Length -ne 0) { throw 'A failed check must not emit build outputs.' }
            }
            else {
                if ($null -ne $failure) { throw "$failure`n$($failure.ScriptStackTrace)" }
                $outputs = ConvertFrom-StringData $outputText
                if ($outputs.should_build -ne $case.Build) { throw "Expected should_build=$($case.Build)." }
                if ($outputs.upstream_commit -ne $packageCommit) { throw 'Incorrect pinned commit.' }
                if ($outputs.upstream_version -ne '2.99.0.1') { throw 'Incorrect source version.' }
                if ($outputs.release_tag -ne 'pcl-2.99.0.1-patched') { throw 'Incompatible downstream tag format.' }
                if ($outputs.upstream_commit_url -ne "https://github.com/test/upstream/commit/$packageCommit") { throw 'Incorrect commit URL.' }
                if ($requestedUris.Count -ne 3 -or $requestedUris[1] -ne $sourceUri) {
                    throw 'Version detection must read the source at the stable package SHA.'
                }
            }
            Write-Host "PASS: $($case.Name)"
        }
        catch {
            throw "FAIL: $($case.Name): $_"
        }
        finally {
            Remove-Item -LiteralPath $env:GITHUB_OUTPUT -Force
        }
    }
}
finally {
    $env:GITHUB_OUTPUT = $previousOutput
}
Write-Host "Passed $($cases.Count) upstream detection scenarios."
