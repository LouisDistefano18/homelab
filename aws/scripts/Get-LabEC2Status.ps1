<#
.SYNOPSIS
    Returns the status and key details of the homelab EC2 instance.

.DESCRIPTION
    Queries AWS for the current state, uptime, instance type, and public IP
    of the homelab EC2 instance. Outputs to console and optionally to HTML report.

.PARAMETER InstanceId
    The EC2 instance ID to query. Defaults to homelab-server-01.

.PARAMETER Report
    If specified, generates an HTML report in the current directory.

.EXAMPLE
    .\Get-LabEC2Status.ps1
    .\Get-LabEC2Status.ps1 -Report
#>

param (
    [string]$InstanceId = "i-023a044160d1287af",
    [switch]$Report
)

# --- Config ---
$Region  = "us-east-1"
$LogPath = "$PSScriptRoot\..\..\logs\aws.log"

# --- Logging ---
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry
    $logDir = Split-Path $LogPath
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    Add-Content -Path $LogPath -Value $entry
}

# --- Query AWS ---
Write-Log "Querying EC2 instance $InstanceId..."

try {
    $RawJson = aws ec2 describe-instances `
        --instance-ids $InstanceId `
        --region $Region `
        --output json | ConvertFrom-Json

    $Instance = $RawJson.Reservations[0].Instances[0]

    $Status = [PSCustomObject]@{
        InstanceId   = $Instance.InstanceId
        Name         = ($Instance.Tags | Where-Object { $_.Key -eq "Name" }).Value
        State        = $Instance.State.Name
        InstanceType = $Instance.InstanceType
        PublicIP     = $Instance.PublicIpAddress
        PrivateIP    = $Instance.PrivateIpAddress
        LaunchTime   = $Instance.LaunchTime
        AZ           = $Instance.Placement.AvailabilityZone
        AMI          = $Instance.ImageId
    }

    # --- Console output ---
    $Status | Format-List

    Write-Log "SUCCESS: Retrieved status for $InstanceId - State: $($Status.State)"

} catch {
    Write-Log "ERROR: Failed to query EC2 - $_"
    exit 1
}

# --- HTML Report ---
if ($Report) {
    $ReportPath = "$PSScriptRoot\..\..\reports\ec2-status-report.html"
    $Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $StateColor = if ($Status.State -eq "running") { "#2ecc71" } else { "#e74c3c" }

    $HTML = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>EC2 Status Report</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; padding: 40px; }
        h1 { color: #00d4ff; }
        .card { background: #16213e; border-radius: 8px; padding: 24px; max-width: 600px; }
        .row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #0f3460; }
        .label { color: #aaa; }
        .value { font-weight: bold; }
        .state { color: $StateColor; font-weight: bold; }
        .footer { margin-top: 20px; color: #555; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Homelab — EC2 Status Report</h1>
    <div class="card">
        <div class="row"><span class="label">Instance ID</span><span class="value">$($Status.InstanceId)</span></div>
        <div class="row"><span class="label">Name</span><span class="value">$($Status.Name)</span></div>
        <div class="row"><span class="label">State</span><span class="state">$($Status.State)</span></div>
        <div class="row"><span class="label">Instance Type</span><span class="value">$($Status.InstanceType)</span></div>
        <div class="row"><span class="label">Public IP</span><span class="value">$($Status.PublicIP)</span></div>
        <div class="row"><span class="label">Private IP</span><span class="value">$($Status.PrivateIP)</span></div>
        <div class="row"><span class="label">Launch Time</span><span class="value">$($Status.LaunchTime)</span></div>
        <div class="row"><span class="label">Availability Zone</span><span class="value">$($Status.AZ)</span></div>
        <div class="row"><span class="label">AMI</span><span class="value">$($Status.AMI)</span></div>
    </div>
    <div class="footer">Generated: $Timestamp</div>
</body>
</html>
"@

    $HTML | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "SUCCESS: HTML report saved to $ReportPath"
    Write-Host "Report saved to: $ReportPath"
}