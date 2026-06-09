<#
.SYNOPSIS
    Ships local homelab logs to the S3 log archival bucket.

.DESCRIPTION
    Uploads the local AD logs to the louislab-logs S3 bucket under a
    year/month/day prefix so they're easy to find later. Optionally writes an
    HTML report of what was uploaded.

.PARAMETER LogPath
    Path to the local logs directory. Defaults to the homelab logs folder.

.PARAMETER Report
    If specified, generates an HTML report of the upload results.

.EXAMPLE
    .\Send-LabLogsToS3.ps1
    .\Send-LabLogsToS3.ps1 -Report
#>

param (
    [string]$LogPath = "$PSScriptRoot\..\..\logs",
    [switch]$Report
)

# --- Config ---
$Bucket     = "louislab-logs"
$Region     = "us-east-1"
$DatePrefix = Get-Date -Format "yyyy/MM/dd"
$S3Prefix   = "ad-logs/$DatePrefix"
$UploadLog  = if ($env:COMPUTERNAME -eq "DC01") { "C:\Scripts\Logs\s3-upload.log" } else { "$PSScriptRoot\..\..\logs\s3-upload.log" }

# --- Logging ---
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry
    $logDir = Split-Path $UploadLog
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    Add-Content -Path $UploadLog -Value $entry
}

# --- Resolve path ---
$ResolvedLogPath = Resolve-Path $LogPath -ErrorAction SilentlyContinue

if (-not $ResolvedLogPath) {
    Write-Log "ERROR: Log path not found: $LogPath"
    exit 1
}

# --- Find log files ---
$LogFiles = Get-ChildItem -Path $ResolvedLogPath -Filter "*.log" -File

if ($LogFiles.Count -eq 0) {
    Write-Log "INFO: No log files found in $ResolvedLogPath - nothing to upload."
    exit 0
}

Write-Log "Found $($LogFiles.Count) log file(s) to upload to s3://$Bucket/$S3Prefix/"

# --- Upload each file ---
$Results = @()

foreach ($File in $LogFiles) {
    $S3Key = "$S3Prefix/$($File.Name)"
    Write-Log "Uploading $($File.Name) to s3://$Bucket/$S3Key..."

    try {
        aws s3 cp $File.FullName "s3://$Bucket/$S3Key" --region $Region | Out-Null

        $Results += [PSCustomObject]@{
            File      = $File.Name
            S3Path    = "s3://$Bucket/$S3Key"
            Size      = "$([math]::Round($File.Length / 1KB, 2)) KB"
            Status    = "SUCCESS"
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }

        Write-Log "SUCCESS: Uploaded $($File.Name)"
    } catch {
        $Results += [PSCustomObject]@{
            File      = $File.Name
            S3Path    = "s3://$Bucket/$S3Key"
            Size      = "$([math]::Round($File.Length / 1KB, 2)) KB"
            Status    = "FAILED"
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        Write-Log "ERROR: Failed to upload $($File.Name) - $_"
    }
}

# --- Summary ---
$Succeeded = ($Results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$Failed    = ($Results | Where-Object { $_.Status -eq "FAILED" }).Count
Write-Log "UPLOAD COMPLETE: $Succeeded succeeded, $Failed failed"

# --- HTML Report ---
if ($Report) {
    $ReportPath = "$PSScriptRoot\..\..\reports\s3-upload-report.html"
    $Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Rows = ""
    foreach ($R in $Results) {
        $Color = if ($R.Status -eq "SUCCESS") { "#2ecc71" } else { "#e74c3c" }
        $Rows += "<tr><td>$($R.File)</td><td>$($R.S3Path)</td><td>$($R.Size)</td><td style='color:$Color;font-weight:bold'>$($R.Status)</td><td>$($R.Timestamp)</td></tr>"
    }

    $HTML  = "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>S3 Upload Report</title>"
    $HTML += "<style>"
    $HTML += "body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; padding: 40px; }"
    $HTML += "h1 { color: #00d4ff; }"
    $HTML += ".summary { background: #16213e; border-radius: 8px; padding: 16px 24px; display: inline-block; margin-bottom: 24px; }"
    $HTML += ".summary span { margin-right: 32px; }"
    $HTML += ".success { color: #2ecc71; font-weight: bold; }"
    $HTML += ".failed { color: #e74c3c; font-weight: bold; }"
    $HTML += "table { width: 100%; border-collapse: collapse; background: #16213e; border-radius: 8px; overflow: hidden; }"
    $HTML += "th { background: #0f3460; padding: 12px 16px; text-align: left; color: #00d4ff; }"
    $HTML += "td { padding: 10px 16px; border-bottom: 1px solid #0f3460; font-size: 13px; }"
    $HTML += ".footer { margin-top: 20px; color: #555; font-size: 12px; }"
    $HTML += "</style></head><body>"
    $HTML += "<h1>Homelab - S3 Log Upload Report</h1>"
    $HTML += "<div class='summary'>"
    $HTML += "<span>Total: <strong>$($Results.Count)</strong></span>"
    $HTML += "<span class='success'>Succeeded: $Succeeded</span>"
    $HTML += "<span class='failed'>Failed: $Failed</span>"
    $HTML += "</div>"
    $HTML += "<table><thead><tr><th>File</th><th>S3 Path</th><th>Size</th><th>Status</th><th>Timestamp</th></tr></thead>"
    $HTML += "<tbody>$Rows</tbody></table>"
    $HTML += "<div class='footer'>Generated: $Timestamp | Bucket: $Bucket | Prefix: $S3Prefix</div>"
    $HTML += "</body></html>"

    $HTML | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "SUCCESS: HTML report saved to $ReportPath"
    Write-Host "Report saved to: $ReportPath"
}