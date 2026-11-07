# aws_setup_timekeep.ps1
#
# Completes Timekeep deployment step 2 (AWS Rekognition) once the AWS CLI is
# authenticated. It is idempotent: re-running it will not duplicate the IAM
# policy, user, or collection.
#
# Usage (after `aws login` or `aws configure`):
#   .\scripts\aws_setup_timekeep.ps1
#   .\scripts\aws_setup_timekeep.ps1 -OrgId <production-org-uuid>
#   .\scripts\aws_setup_timekeep.ps1 -CreateAccessKey
#
# -CreateAccessKey writes the new key pair to a local file that is NOT printed
# to the console. Copy the secret into the hermes secret store, then delete the
# file.

[CmdletBinding()]
param(
  [string]$Region = 'sa-east-1',
  [string]$UserName = 'yabil-timekeep-rekognition',
  [string]$PolicyName = 'YabilTimekeepRekognition',
  [string]$OrgId = '',
  [switch]$CreateAccessKey
)

$ErrorActionPreference = 'Stop'

$Aws = 'C:\Users\akhta\AppData\Local\Programs\Amazon\AWSCLIV2\aws.exe'
if (-not (Test-Path $Aws)) {
  $command = Get-Command aws -ErrorAction SilentlyContinue
  if (-not $command) { throw 'AWS CLI not found. Install it or set $Aws manually.' }
  $Aws = $command.Source
}

function Invoke-AwsRaw {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $output = & $Aws @Arguments 2>&1
  [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output   = ($output | Out-String).Trim()
  }
}

function Invoke-Aws {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $result = Invoke-AwsRaw @Arguments
  if ($result.ExitCode -ne 0) {
    throw "aws $($Arguments -join ' ') failed:`n$($result.Output)"
  }
  return $result.Output
}

function Write-ExpectedOrThrow {
  param([object]$Result, [string]$ExpectedPattern, [string]$Message)
  if ($Result.ExitCode -eq 0) { return $false }
  if ($Result.Output -match $ExpectedPattern) { Write-Host $Message; return $true }
  throw "AWS call failed:`n$($Result.Output)"
}

Write-Host '== Identity ==' -ForegroundColor Cyan
$identityJson = Invoke-Aws sts get-caller-identity --output json
Write-Host $identityJson
$accountId = ($identityJson | ConvertFrom-Json).Account

Write-Host "`n== IAM policy: $PolicyName ==" -ForegroundColor Cyan
$policyDocument = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rekognition:CreateCollection",
        "rekognition:DescribeCollection",
        "rekognition:IndexFaces",
        "rekognition:SearchFacesByImage",
        "rekognition:ListFaces",
        "rekognition:DeleteFaces"
      ],
      "Resource": "*"
    }
  ]
}
'@

$tempPolicy = Join-Path $env:TEMP 'yabil-timekeep-rekognition-policy.json'
$policyDocument | Set-Content -Path $tempPolicy -Encoding ascii

$policyArn = "arn:aws:iam::${accountId}:policy/$PolicyName"
$createPolicy = Invoke-AwsRaw iam create-policy --policy-name $PolicyName --policy-document "file://$tempPolicy" --output json
$existed = Write-ExpectedOrThrow -Result $createPolicy -ExpectedPattern 'EntityAlreadyExists' -Message "Policy already exists: $policyArn"
if (-not $existed) { Write-Host "Created policy: $policyArn" }
Remove-Item $tempPolicy -Force -ErrorAction SilentlyContinue

Write-Host "`n== IAM user: $UserName ==" -ForegroundColor Cyan
$createUser = Invoke-AwsRaw iam create-user --user-name $UserName --output json
$userExisted = Write-ExpectedOrThrow -Result $createUser -ExpectedPattern 'EntityAlreadyExists' -Message "User already exists: $UserName"
if (-not $userExisted) { Write-Host "Created user: $UserName" }
Invoke-Aws iam attach-user-policy --user-name $UserName --policy-arn $policyArn | Out-Null
Write-Host "Attached $PolicyName to $UserName"

if ($CreateAccessKey) {
  Write-Host "`n== Access key ==" -ForegroundColor Cyan
  $keysJson = Invoke-Aws iam list-access-keys --user-name $UserName --output json
  $keys = $keysJson | ConvertFrom-Json
  $keyCount = @($keys.AccessKeyMetadata).Count
  if ($keyCount -ge 2) {
    throw "User already has $keyCount access keys. Delete an old key in IAM first."
  }
  $keyJson = Invoke-Aws iam create-access-key --user-name $UserName --output json
  $key = $keyJson | ConvertFrom-Json
  $credentialFile = Join-Path (Get-Location) 'aws-timekeep-credentials.txt'
  @(
    '# Yabil Timekeep AWS credentials',
    "# created $(Get-Date -Format o)",
    "AWS_REGION=$Region",
    "AWS_ACCESS_KEY_ID=$($key.AccessKey.AccessKeyId)",
    "AWS_SECRET_ACCESS_KEY=$($key.AccessKey.SecretAccessKey)",
    'REKOGNITION_COLLECTION_PREFIX=yabil-timekeep',
    'REKOGNITION_SIMILARITY_THRESHOLD=90',
    'REKOGNITION_AMBIGUITY_MARGIN=2'
  ) | Set-Content -Path $credentialFile -Encoding ascii
  Write-Host "Access key ID: $($key.AccessKey.AccessKeyId)"
  Write-Host "Secret written to: $credentialFile"
  Write-Host 'Copy it into the hermes secret store, then delete the file.'
} else {
  Write-Host "`nSkipping access-key creation. Re-run with -CreateAccessKey when ready."
}

if ($OrgId) {
  Write-Host "`n== Rekognition collection ==" -ForegroundColor Cyan
  $collectionId = "yabil-timekeep-$OrgId"
  $createCollection = Invoke-AwsRaw rekognition create-collection --collection-id $collectionId --region $Region --output json
  $collectionExisted = Write-ExpectedOrThrow -Result $createCollection -ExpectedPattern 'ResourceAlreadyExistsException' -Message "Collection already exists: $collectionId"
  if (-not $collectionExisted) { Write-Host "Created collection: $collectionId" }
  Invoke-Aws rekognition describe-collection --collection-id $collectionId --region $Region --output json | Write-Host
} else {
  Write-Host "`nNo -OrgId supplied. The backend creates yabil-timekeep-<org-uuid> on the first enrollment."
}

Write-Host "`n== Environment for the backend ==" -ForegroundColor Cyan
@"
AWS_REGION=$Region
AWS_ACCESS_KEY_ID=<from the access-key file or hermes secret store>
AWS_SECRET_ACCESS_KEY=<from the access-key file or hermes secret store>
REKOGNITION_COLLECTION_PREFIX=yabil-timekeep
REKOGNITION_SIMILARITY_THRESHOLD=90
REKOGNITION_AMBIGUITY_MARGIN=2
"@ | Write-Host

Write-Host "`nDone." -ForegroundColor Green
