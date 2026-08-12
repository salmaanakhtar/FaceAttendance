# Build a release APK and publish it as a GitHub release (auto-update source).
# Usage: publish_release.ps1 -Tag v1.0.1 [-ApiBase https://...] [-Notes "what changed"]
param(
  [Parameter(Mandatory=$true)][string]$Tag,
  [string]$ApiBase = 'https://faceattendance-api.salmaan.dev',
  [string]$Notes = 'FaceAttendance release'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location (Join-Path $root 'app')

$defineApi = "--dart-define=API_BASE=$ApiBase"
$defineVer = "--dart-define=APP_VERSION=$Tag"
& flutter build apk --release $defineApi $defineVer
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$apk = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
gh release create $Tag $apk --repo salmaanakhtar/FaceAttendance --title "FaceAttendance $Tag" --notes $Notes
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed (does the tag already exist?)' }

# Keep a local copy next to the project for sideloading.
$releases = Join-Path $root 'app\releases'
New-Item -ItemType Directory -Path $releases -Force | Out-Null
Copy-Item $apk (Join-Path $releases "FaceAttendance-$Tag-lan.apk") -Force

Write-Output "Published $Tag -> https://github.com/salmaanakhtar/FaceAttendance/releases/tag/$Tag"
Write-Output "Local APK   -> $releases\FaceAttendance-$Tag-lan.apk"
