<#
.SYNOPSIS
    Creates a new Active Directory user in the LAB domain.

.DESCRIPTION
    Creates a user in lab.local, drops them in the Users OU, sets a starting
    password, and adds them to a group based on their job title. Logs each step
    to a timestamped file under C:\Scripts\Logs.

.PARAMETER FirstName
    User's first name.

.PARAMETER LastName
    User's last name.

.PARAMETER Title
    User's job title. Determines group membership.

.PARAMETER Department
    User's department.

.EXAMPLE
    .\New-LabUser.ps1 -FirstName "Jane" -LastName "Doe" -Title "Compliance Officer" -Department "Compliance"
#>

param (
    [Parameter(Mandatory)]
    [string]$FirstName,

    [Parameter(Mandatory)]
    [string]$LastName,

    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [string]$Department
)

# --- Config ---
$Domain       = "lab.local"
$UserOU       = "OU=Users,OU=LAB,DC=lab,DC=local"
$DefaultPass  = ConvertTo-SecureString "Welcome@Lab1!" -AsPlainText -Force
$LogPath = "C:\Scripts\Logs\onboarding-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# --- Derived values ---
$Username     = "$($FirstName.ToLower()).$($LastName.ToLower())"
$DisplayName  = "$FirstName $LastName"
$UPN          = "$Username@$Domain"

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

# --- Check for duplicate ---
if (Get-ADUser -Filter { SamAccountName -eq $Username } -ErrorAction SilentlyContinue) {
    Write-Log "ERROR: User $Username already exists. Aborting."
    exit 1
}

# --- Create user ---
try {
    New-ADUser `
        -SamAccountName       $Username `
        -UserPrincipalName    $UPN `
        -Name                 $DisplayName `
        -GivenName            $FirstName `
        -Surname              $LastName `
        -Title                $Title `
        -Department           $Department `
        -Path                 $UserOU `
        -AccountPassword      $DefaultPass `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires  $true `
        -Enabled              $true

    Write-Log "SUCCESS: Created user $Username ($DisplayName) in $UserOU"
} catch {
    Write-Log "ERROR: Failed to create user $Username - $_"
    exit 1
}

# --- Group assignment based on title ---
$GroupMap = @{
    "Portfolio Manager"  = "Portfolio Managers"
    "IT Administrator"   = "IT Admins"
    "Compliance Officer" = "Portfolio Managers"
}

$TargetGroup = $GroupMap[$Title]

if ($TargetGroup) {
    try {
        Add-ADGroupMember -Identity $TargetGroup -Members $Username
        Write-Log "SUCCESS: Added $Username to group '$TargetGroup'"
    } catch {
        Write-Log "WARNING: Could not add $Username to group '$TargetGroup' - $_"
    }
} else {
    Write-Log "INFO: No group mapping found for title '$Title' - manual assignment required"
}

# --- Summary ---
Write-Log "ONBOARDING COMPLETE: $DisplayName | $Username@$Domain | $Title | $Department"