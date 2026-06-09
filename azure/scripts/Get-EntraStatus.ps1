<#
.SYNOPSIS
    Returns the hybrid-identity status of the homelab Entra ID tenant.

.DESCRIPTION
    Queries Microsoft Entra ID through the Azure CLI for the tenant, the
    directory sync state (whether on-prem AD is syncing and when it last ran),
    and how many users and groups are synced from the domain controller. Outputs
    to console and optionally to an HTML report.

    Needs the Azure CLI signed in (az login). If the directory hasn't been
    connected to on-prem AD yet, sync shows as "not configured" rather than
    failing — that's the expected state until the Cloud Sync agent is live.

.PARAMETER Report
    If specified, generates an HTML report in the reports/ directory.

.EXAMPLE
    .\Get-EntraStatus.ps1
    .\Get-EntraStatus.ps1 -Report
#>

param (
    [switch]$Report
)

# --- Config ---
$LogPath = "$PSScriptRoot\..\..\logs\azure.log"

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

# --- Query Entra ---
Write-Log "Querying Entra ID tenant status..."

try {
    $Account = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $Account) { throw "Azure CLI not signed in. Run 'az login' first." }

    # Directory sync state from the organization object.
    $Org = (az rest --method GET `
        --url "https://graph.microsoft.com/v1.0/organization?`$select=displayName,onPremisesSyncEnabled,onPremisesLastSyncDateTime" `
        --output json 2>$null | ConvertFrom-Json).value[0]

    # The default (fallback) domain, read authoritatively from the directory
    # rather than the CLI's cached tenantDefaultDomain, which can lag a rename.
    $DefaultDomain = (az rest --method GET `
        --url "https://graph.microsoft.com/v1.0/domains?`$select=id,isDefault" `
        --output json 2>$null | ConvertFrom-Json).value |
        Where-Object { $_.isDefault } | Select-Object -First 1 -ExpandProperty id
    if (-not $DefaultDomain) { $DefaultDomain = $Account.tenantDefaultDomain }

    # Count objects synced from on-prem AD (the LAB OU tree: users + groups).
    $SyncedUsers = az ad user list `
        --filter "onPremisesSyncEnabled eq true" `
        --query "length(@)" --output tsv 2>$null
    $SyncedGroups = az ad group list `
        --filter "onPremisesSyncEnabled eq true" `
        --query "length(@)" --output tsv 2>$null

    $SyncEnabled = [bool]$Org.onPremisesSyncEnabled
    $LastSync    = if ($Org.onPremisesLastSyncDateTime) {
        ([datetime]$Org.onPremisesLastSyncDateTime).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    } else { "never (sync not configured)" }

    $Status = [PSCustomObject]@{
        Tenant       = $DefaultDomain
        TenantId     = $Account.tenantId
        Directory    = $Org.displayName
        SignedInAs   = $Account.user.name
        SyncEnabled  = $SyncEnabled
        LastSync     = $LastSync
        SyncedUsers  = if ($SyncedUsers) { [int]$SyncedUsers } else { 0 }
        SyncedGroups = if ($SyncedGroups) { [int]$SyncedGroups } else { 0 }
    }

    # --- Console output ---
    $Status | Format-List

    Write-Log "SUCCESS: Retrieved Entra status for $($Status.Tenant) - Sync enabled: $($Status.SyncEnabled)"

} catch {
    Write-Log "ERROR: Failed to query Entra ID - $_"
    exit 1
}

# --- HTML Report ---
if ($Report) {
    $ReportPath = "$PSScriptRoot\..\..\reports\entra-status-report.html"
    $Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $SyncColor = if ($Status.SyncEnabled) { "#2ecc71" } else { "#f1c40f" }
    $SyncText  = if ($Status.SyncEnabled) { "enabled" } else { "not configured" }

    $HTML = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Entra ID Status Report</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; padding: 40px; }
        h1 { color: #00d4ff; }
        .card { background: #16213e; border-radius: 8px; padding: 24px; max-width: 600px; }
        .row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #0f3460; }
        .label { color: #aaa; }
        .value { font-weight: bold; }
        .state { color: $SyncColor; font-weight: bold; }
        .footer { margin-top: 20px; color: #555; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Homelab — Entra ID Status Report</h1>
    <div class="card">
        <div class="row"><span class="label">Tenant</span><span class="value">$($Status.Tenant)</span></div>
        <div class="row"><span class="label">Tenant ID</span><span class="value">$($Status.TenantId)</span></div>
        <div class="row"><span class="label">Directory</span><span class="value">$($Status.Directory)</span></div>
        <div class="row"><span class="label">Signed in as</span><span class="value">$($Status.SignedInAs)</span></div>
        <div class="row"><span class="label">Directory sync</span><span class="state">$SyncText</span></div>
        <div class="row"><span class="label">Last sync</span><span class="value">$($Status.LastSync)</span></div>
        <div class="row"><span class="label">Synced users</span><span class="value">$($Status.SyncedUsers)</span></div>
        <div class="row"><span class="label">Synced groups</span><span class="value">$($Status.SyncedGroups)</span></div>
    </div>
    <div class="footer">Generated: $Timestamp</div>
</body>
</html>
"@

    $HTML | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "SUCCESS: HTML report saved to $ReportPath"
    Write-Host "Report saved to: $ReportPath"
}
