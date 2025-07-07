<#
.SYNOPSIS
    This PowerShell Script takes Azure Subscriptions and converts Premium SSD V1 disks to Premium SSD V2 disks. It will skip all unsupported disk types such as OS disks. It will also attempt to disable caching, bursting, and double encryption to meet migration requirements.
    Those features need to be disabled in order to perform the migration to Premium SSD V2. The migration path for disks that do not meet requirements involves creating snapshots and deploying new disks from snapshot which is not covered in this script.
    See links below for more information
    Information/Logging is collected and outputted to a text file in the same folder the script was executed in.

.PARAMETER SubscriptionId
    Specify the SubscriptionID to target.

.EXAMPLE
    PS C:\> .\AzConvertV1toV2Disks -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxx"

.NOTES
    AUTHOR: ROB SIANO - SENIOR CLOUD SOLUTION ARCHITECT | Azure Infrastructure | Microsoft
    PERMISSIONS: Ensure you have the necessary permissions to stop/start VMs and update disk configurations in the specified subscriptions.
    REQUIREMENTS: Azure PowerShell Module (Az) installed and updated to the latest version.

.LINK
    https://github.com/RobSiano
    https://learn.microsoft.com/en-us/azure/virtual-machines/disks-convert-types?tabs=azure-powershell#migrate-to-premium-ssd-v2-or-ultra-disk-using-snapshots

.DESCRIPTION
    DISCLAIMER
    This script is provided as a personal/community tool to assist with the conversion of Azure Premium SSD V1 disks to Premium SSD V2 disks. It is not an official Microsoft product or service.
    Use of this script is at your own risk, and it is recommended to test in a non-production environment before using it in production.
    Please note that while being developed by a Microsoft employee, AzConvertV1toV2Disks.ps1 is not supported by Microsoft.
    There are none implicit or explicit obligations related to this project, it is provided 'as is' with no warranties and confer no rights.
    The author is not responsible for any issues that may arise from the use of this script.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

Write-Host "AzConvertV1toV2Disks Script started at $(Get-Date)" -ForegroundColor Cyan

# Create a Log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = ".\AzConvertV1toV2DisksLog_$timestamp.txt"
Start-Transcript -Path $LogFile -Append
Write-Host "AzConvertV1toV2Disks logging started to file $LogFile" -ForegroundColor Cyan

# Check if Az module is installed
#if (-not (Get-Module -ListAvailable -Name Az)) {
#    Write-Host "Az module is not installed. Installing Az module..." -ForegroundColor Yellow
#    Install-Module -Name Az -AllowClobber -Force
#} else {
#   Write-Host "Az module is already installed." -ForegroundColor Green
#}   

# Import the Az module and check if it has imported successfully
#Import-Module Az -Force
#if (Get-Module -Name Az) {              
#    Write-Host "Az module imported successfully." -ForegroundColor Green
#} else {
#    Write-Host "Failed to import Az module. Exiting script." -ForegroundColor Red
#    Stop-Transcript
#    exit
#}

# Check if the user has provided Subscription ID
if (-not $SubscriptionId) {
    Write-Host "No valid Subscription ID provided. Exiting script." -ForegroundColor Red
    Stop-Transcript
    exit
} else {
    Write-Host "Processing Subscription ID: $SubscriptionId" -ForegroundColor Cyan
}

# Validate the SubscriptionId input format 
# This regex checks for a valid ID format, allowing for multiple IDs separated by commas
$SubscriptionId = $SubscriptionId -replace '\s+', '' # Remove any whitespace
if ($SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(,[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})*$') {
    Write-Host "Invalid Subscription ID format. Please provide valid Subscription ID." -ForegroundColor Red
    Stop-Transcript
    exit
}   
else {
    Write-Host "Valid Subscription ID format detected." -ForegroundColor Cyan
}

# Connect to Azure Account
$ConnectAzAccount = Connect-AzAccount -Subscription $SubscriptionId -InformationAction SilentlyContinue -WarningAction SilentlyContinue
if ($ConnectAzAccount){
    Write-Host "Successfully connected to Azure." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to Azure. Exiting script." -ForegroundColor Red
    Stop-Transcript
    exit    
}

# Set the subscription context
$setazcontext = Set-AzContext -SubscriptionId $SubscriptionId
if ($setazcontext.Subscription.id -eq $SubscriptionId){
    Write-Host "Successfully set context to subscription: $SubscriptionId to ensure correct Subscription selected" -ForegroundColor Green
} else {
    Write-Host "Failed to set context to subscription: $SubscriptionId. Exiting script." -ForegroundColor Red
    Stop-Transcript
    Exit
}

# Ensure the user has the necessary permissions to manage disks in the specified subscriptions
$permissions = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" | Where-Object { $_.RoleDefinitionName -eq "Contributor" -or $_.RoleDefinitionName -eq "Owner" }
if (-not $permissions) {    
    Write-Host "You do not have the necessary permissions to manage disks in the specified subscription. Please ensure you have 'Contributor' or 'Owner' role." -ForegroundColor Red
    Stop-Transcript
    exit
} else {
    Write-Host "You have the necessary permissions to manage disks in the specified subscription." -ForegroundColor Green
}

# ---------------------------------Start of Convert-Disks function---------------------------------------
function Convert-Disks {
    param ([string]$SubscriptionId)

    Write-Host "Starting disk conversion for subscription: $SubscriptionId" -ForegroundColor Green

    # Get all Premium SSD v1 managed disks that are not OS disks
    $disks = Get-AzDisk | Where-Object {$_.OsType -eq $null -and $_.Sku.Name -eq "Premium_LRS"}

    # Ensure disks are found
    if ($disks) {
    Write-Host "Found $($disks.Count) Premium SSD v1 disks that can be converted" -ForegroundColor Green
    } else {
        Write-Host "No Premium SSD v1 disks found in subscription $SubscriptionId" -ForegroundColor Yellow
        return
    }

    # Loop through each disk and convert it to Premium SSD v2
    foreach ($disk in $disks) {
            $diskname = $disk.name
            Write-Host "Processing disk: $diskname" -ForegroundColor Cyan
            if ($disk.ManagedBy) {
                # Check if Disk is attached
                $vm = Get-AzVM -ResourceGroupName $disk.ResourceGroupName -Name $disk.managedby.split('/')[-1]
                $vmstatus = get-azvm -status -resourcegroupname $vm.ResourceGroupName -name $vm.Name
                if ($vm -ne $null -and $vmstatus.statuses.DisplayStatus[-1] -eq "VM deallocated") {
                    Write-Host "Disk $diskname is attached to VM: $($vm.Name) and VM is already deallocated. Proceeding with conversion." -ForegroundColor Cyan
                } else {
                    Write-Host "Stopping VM: $($vm.Name)" -ForegroundColor Green
                    $stoppedVM = Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
                    $vmrecheck = get-azvm -status -resourcegroupname $vm.ResourceGroupName -name $vm.Name
                    if ($vmrecheck.statuses.DisplayStatus[-1] -eq "VM deallocated") {
                        Write-Host "Successfully stopped VM: $($vm.Name)" -ForegroundColor Green
                        $VMstopped = $true
                    } else {
                        Write-Host "ERROR stopping VM: $($vm.Name). Skipping disk conversion." -ForegroundColor Red
                        continue
                    }
                }
            }
            else {
                Write-Host "Disk $diskname is not attached to any VM. Proceeding with conversion." -ForegroundColor Cyan
                $VMstopped = $false
            }

            # Disable disk Caching if enabled (Unsupported on PremiumV2 disks)
            $cachecheck = $vm.StorageProfile.DataDisks | Where-Object { $_.Name -eq $disk.name} | Select-Object Caching
            if ($cachecheck.Caching -ne "None") {
            $setdisk = Set-AzVMDataDisk -VM $vm -Name $disk.name -Caching None
            $updatevm = Update-AzVM -VM $vm -ResourceGroupName $vm.ResourceGroupName
                if ($updatevm.IsSuccessStatusCode -eq $true) {
                    Write-Host "Disk $diskname caching successfully set to None." -ForegroundColor Green
                } else {
                    Write-Host "ERROR setting caching to None for disk $diskname. Skipping disk." -ForegroundColor Red
                    continue
                        }
            } else {
                Write-Host "Disk $diskname already has caching set to None." -ForegroundColor Cyan    
            }

            # Disable disk bursting (Bursting can only be deactivated 12 hours after activation)
            if ($disk.BurstingEnabled -ne $false) {
                    
                    Write-Host "Disabling bursting on disk: $diskname" -ForegroundColor Cyan
                    $diskconfig = New-AzDiskUpdateConfig -BurstingEnabled $false
                    $diskupdate = Update-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.name -Diskupdate $diskconfig -ErrorAction SilentlyContinue
                    if ($diskupdate.ProvisioningState -eq "Succeeded") {
                        Write-Host "Successfully disabled bursting on disk: $diskname" -ForegroundColor Green
                    } else {
                        Write-Host "ERROR disabling bursting on disk $diskname. Check Activity Logs. Please Note: Bursting can only be deactivated 12 hours after activation. Skipping disk." -ForegroundColor Red
                        continue
                    } 
            } else{
                    Write-Host "ERROR disabling bursting on disk $diskname. Check Activity Logs. Please Note: Bursting can only be deactivated 12 hours after activation." -ForegroundColor Red
                    continue    
                }

            # Update encryption settings from double to single encryption (You will need to re-enable double encryption after conversion)
            $DiskEncryptionType= $disk.Encryption.Type
            if ($DiskEncryptionType -ne "EncryptionAtRestWithPlatformAndCustomerKeys"){
                Write-Host "Disk $diskname does not have Double Encryption Enabled. Skipping encryption update." -ForegroundColor Cyan
                } else {
                    $diskEncryptionSetName = $disk.Encryption.DiskEncryptionSet.Id.Split('/')[-1]
                    $diskEncryptionSet = Get-AzDiskEncryptionSet -ResourceGroupName $disk.ResourceGroupName -Name $diskEncryptionSetName
                    if ($diskEncryptionSet -ne $null) {
                        Write-Host "Found Disk Encryption Set: $($diskEncryptionSet.Name)" -ForegroundColor Cyan
                        $ChangeDisk = New-AzDiskUpdateConfig -EncryptionType "EncryptionAtRestWithCustomerKey” -DiskEncryptionSetId $diskEncryptionSet.Id
                        $UpdateDisk = Update-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name -diskupdate $ChangeDisk
                        if ($UpdateDisk.IsSuccessStatusCode -eq $true) {
                            Write-Host "Updated encryption settings for disk: $diskname" -ForegroundColor Green
                        } else{
                            Write-Host "ERROR updating encryption settings for disk $diskname. Skipping disk." -ForegroundColor Red
                            continue
                            }
                        }
                    }

            # Update the disk SKU to PremiumV2_LRS
            $diskmigration = get-azdisk $disk.Name -ResourceGroupName $disk.ResourceGroupName
            $diskconfignew = New-AzDiskUpdateConfig -skuname "PremiumV2_LRS" -BurstingEnabled $false
            $updateAzDisk = Update-AzDisk -ResourceGroupName $diskmigration.ResourceGroupName -DiskName $diskmigration.Name -Diskupdate $diskconfignew
            if ($updateAzDisk.Sku.name -eq "PremiumV2_LRS") {
                Write-Host "Successfully converted disk: $diskname to Premium SSD v2" -ForegroundColor Green
            } else {
            Write-Host "ERROR converting disk $diskname to Premium SSD v2. Skipping disk." -ForegroundColor Red
            continue
            }
        
            # Start the VM if it was stopped for the conversion
            if ($disk.ManagedBy -and $vm -ne $null -and $VMstopped -eq $true) {
                Write-Host "Starting VM: $($vm.Name)" -ForegroundColor Green
                $startVM = Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
                if($startVM.IsSuccessStatusCode -eq $true) {
                    Write-Host "Successfully started VM: $vm.Name" -ForegroundColor Green
                } else {
                    Write-Host "ERROR starting VM: $vm.Name. Please check Activity Logs." -ForegroundColor Red
                    continue
                }
            }
            else {
                Write-Host "Disk $diskname was not attached to any VM or VM was already deallocated. Skipping VM start." -ForegroundColor Cyan
            }
    }
}
# ----------------------------------End of Convert-Disks function----------------------------------------


# Call the function to convert disks for each subscription
Try {
    Convert-Disks -SubscriptionId $SubscriptionId
}
catch {
    Write-Host "ERROR in Convert-Disks function: $_" -ForegroundColor Red
}

# End of script
Write-Host "AzConvertV1toV2Disks Script completed at $(Get-Date)" -ForegroundColor Green
Stop-Transcript