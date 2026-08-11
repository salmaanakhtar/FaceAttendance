# One-shot visual QA via a vision-capable model (opencode CLI).
# Usage: vision_qc.ps1 -Image <path> [-Prompt <string>] [-Model <string>]
param(
  [Parameter(Mandatory=$true)][string]$Image,
  [string]$Prompt = 'Describe this screenshot in detail: what screen is shown, all text verbatim, colors, layout, spacing, alignment, visual glitches, quality verdict. Be specific.',
  [string]$Model = 'opencode-go/qwen3.7-plus'
)
$ErrorActionPreference = 'Stop'
$out = Join-Path $env:TEMP 'vision-qc.out'
$err = Join-Path $env:TEMP 'vision-qc.err'
Remove-Item $out, $err -ErrorAction SilentlyContinue

$inner = @"
`$env:OPENCODE_DISABLE_NONTTY='1'
opencode run --auto -m '$Model' `"$Prompt`" -f `"$Image`"
"@
$script = Join-Path $env:TEMP 'vision-qc-cmd.ps1'
Set-Content $script -Value $inner -Encoding UTF8

$p = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script) -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if (-not $p.WaitForExit(240000)) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Write-Output 'STALLED'
  Get-Content $err -ErrorAction SilentlyContinue | Select-Object -First 10
  exit 1
}
Get-Content $out -ErrorAction SilentlyContinue
