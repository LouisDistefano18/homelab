<#
.SYNOPSIS
    Offboards an Active Directory user from the LAB domain.

.DESCRIPTION
    Offboards a user: disables the account, strips every group membership, and
    moves it to the Disabled OU (creating that OU if it's missing). Each step is
    logged to a timestamped file under C:\Scripts\Logs.

.PARAMETER Username
    The SamAccountName of the user to offboard.

.EXAMPLE
    .\Remove-LabUser.ps1 -Username "test.user"
#>

param (
    [Parameter(Mandatory)]
    [string]$Username
)

# --- Config ---
$DisabledOU = "OU=Disabled,OU=LAB,DC=lab,DC=local"
$LogPath    = "C:\Scripts\Logs\offboarding-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# --- Logging function ---
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry
}

# --- Ensure log directory exists ---
if (-not (Test-Path "C:\Scripts\Logs")) {
    New-Item -ItemType Directory -Path "C:\Scripts\Logs" | Out-Null
}

# --- Check user exists ---
$User = Get-ADUser -Filter { SamAccountName -eq $Username } -Properties MemberOf, DisplayName -ErrorAction SilentlyContinue

if (-not $User) {
    Write-Log "ERROR: User $Username not found in Active Directory. Aborting."
    exit 1
}

Write-Log "OFFBOARDING STARTED: $($User.DisplayName) ($Username)"

# --- Disable account ---
try {
    Disable-ADAccount -Identity $Username
    Write-Log "SUCCESS: Disabled account $Username"
} catch {
    Write-Log "ERROR: Failed to disable account $Username - $_"
    exit 1
}

# --- Remove all group memberships ---
$Groups = $User.MemberOf

foreach ($Group in $Groups) {
    try {
        Remove-ADGroupMember -Identity $Group -Members $Username -Confirm:$false
        Write-Log "SUCCESS: Removed $Username from $Group"
    } catch {
        Write-Log "WARNING: Could not remove $Username from $Group - $_"
    }
}

# --- Ensure Disabled OU exists ---
if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $DisabledOU } -ErrorAction SilentlyContinue)) {
    try {
        New-ADOrganizationalUnit -Name "Disabled" -Path "OU=LAB,DC=lab,DC=local"
        Write-Log "INFO: Created Disabled OU"
    } catch {
        Write-Log "ERROR: Could not create Disabled OU - $_"
        exit 1
    }
}

# --- Move to Disabled OU ---
try {
    Move-ADObject -Identity $User.DistinguishedName -TargetPath $DisabledOU
    Write-Log "SUCCESS: Moved $Username to $DisabledOU"
} catch {
    Write-Log "ERROR: Failed to move $Username to Disabled OU - $_"
}

# --- Summary ---
Write-Log "OFFBOARDING COMPLETE: $($User.DisplayName) | $Username | Account disabled and moved to Disabled OU"