<#
.SYNOPSIS
  Uploads the zlibx-MD3 release signing material to GitHub Actions secrets.

.DESCRIPTION
  Reads android/key.properties and the keystore it points at, then sets the
  five repository secrets the release workflow needs. Nothing is written to
  the repository; the keystore is only base64-encoded in memory.

  The keystore MUST be the one that signed v1.6.2
  (SHA-256 C93F9658...D75C09), otherwise installed users cannot upgrade in
  place.

.EXAMPLE
  pwsh -File tool/set-ci-secrets.ps1
  pwsh -File tool/set-ci-secrets.ps1 -Repo Isilsolme/zlibx-MD3
#>
param(
  [string]$Repo = 'Isilsolme/zlibx-MD3',
  [string]$KeyProperties = (Join-Path $PSScriptRoot '..\android\key.properties'),
  [string]$ExpectedCertSha256 = 'C93F965833ABA6EA1C775A52989A593B2BE57B7512C43F747DD76FD330D75C09'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $KeyProperties)) {
  throw "key.properties not found at $KeyProperties. Point -KeyProperties at the file that holds storeFile/storePassword/keyAlias/keyPassword."
}

$props = @{}
foreach ($line in Get-Content -LiteralPath $KeyProperties) {
  $trimmed = $line.Trim()
  if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
  $idx = $trimmed.IndexOf('=')
  if ($idx -lt 1) { continue }
  $props[$trimmed.Substring(0, $idx).Trim()] = $trimmed.Substring($idx + 1).Trim()
}

foreach ($name in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
  if (-not $props.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($props[$name])) {
    throw "key.properties is missing '$name'."
  }
}

$keystore = $props['storeFile']
if (-not [System.IO.Path]::IsPathRooted($keystore)) {
  # Gradle resolves a relative storeFile against android/app.
  $keystore = Join-Path (Split-Path -Parent $KeyProperties) (Join-Path 'app' $keystore)
}
if (-not (Test-Path -LiteralPath $keystore)) {
  throw "Keystore not found at $keystore"
}

$bytes = [System.IO.File]::ReadAllBytes($keystore)
$b64 = [Convert]::ToBase64String($bytes)
Write-Host ("Keystore: {0} ({1:N0} bytes)" -f $keystore, $bytes.Length)

function Set-RepoSecret([string]$Name, [string]$Value) {
  $Value | gh secret set $Name --repo $Repo
  Write-Host "  set $Name"
}

Write-Host "Uploading secrets to $Repo ..."
Set-RepoSecret 'KEYSTORE_BASE64' $b64
Set-RepoSecret 'KEYSTORE_PASSWORD' $props['storePassword']
Set-RepoSecret 'KEY_PASSWORD' $props['keyPassword']
Set-RepoSecret 'KEY_ALIAS' $props['keyAlias']
if (-not [string]::IsNullOrWhiteSpace($ExpectedCertSha256)) {
  Set-RepoSecret 'EXPECTED_CERT_SHA256' $ExpectedCertSha256
}

Write-Host ''
gh secret list --repo $Repo
