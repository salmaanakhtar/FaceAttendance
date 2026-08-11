# Build a release APK and publish it as a GitHub release (auto-update source).
# Usage: publish_release.ps1 -Tag v0.1.2 [-ApiBase http://192.168.1.169:4747] [-Notes "what changed"]
param(
  [Parameter(Mandatory=$true)][string]$Tag,
  [string]$ApiBase = 'http://192.168.1.169:4747',
  [string]$Notes = 'FaceAttendance release'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location (Join-Path $root 'app')

flutter build apk --release --dart-define="API_BASE=$ApiBase" --dart-define="APP_VERSION=$Tag"
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$apk = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
gh release create $Tag $apk --repo salmaanakhtar/FaceAttendance --title "FaceAttendance $Tag" --notes $Notes
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed (does the tag already exist?)' }

Write-Output "Published $Tag -> https://github.com/salmaanakhtar/FaceAttendance/releases/tag/$Tag"
