<#
.SYNOPSIS
    This PowerShell Script takes Azure Subscriptions and converts Premium SSD V1 disks to Premium SSD V2 disks. It will skip all unsupported disk types such as OS disks. It will also attempt to disable caching, bursting, and double encryption to meet migration requirements.
    Those features need to be disabled in order to perform the migration to Premium SSD V2. Azure Backup policies must also be on Enhanced or disabled before performing the migration, the code will check that this condition is met but will not change your backup policy or disable it.
    The migration path for disks that do not meet requirements involves creating snapshots and deploying new disks from snapshot which is not covered in this code.
    See links below for more information. Information/Logging is collected and outputted to a text file in the same folder the script was executed in.

.PARAMETER SubscriptionId
    Specify the SubscriptionID to target.

.EXAMPLE
    PS C:\> .\AzConvertV1toV2Disks -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxx"
    If run the code without a SubscriptionID, the script will prompt you to select a CSV file containing SubscriptionID, VirtualMachine, and ResourceGroup Names.

.NOTES
    AUTHOR: ROB SIANO - SENIOR CLOUD SOLUTION ARCHITECT | Azure Infrastructure | Microsoft
    PERMISSIONS: Ensure you have the necessary permissions to stop/start VMs and update disk configurations in the specified subscriptions. (code will validate)
    REQUIREMENTS: Azure PowerShell Module (Az) installed and updated to the latest version.(code will validate and install if it is not detected)

.LINK
    https://github.com/RobSiano/AzConvertV1toV2Disks/blob/main/AzConvertV1toV2Disks.ps1
    https://learn.microsoft.com/en-us/azure/virtual-machines/disks-convert-types?tabs=azure-powershell#migrate-to-premium-ssd-v2-or-ultra-disk-using-snapshots

.DESCRIPTION
    DISCLAIMER
    This script is provided as a personal/community tool to assist with the conversion of Azure Premium SSD V1 disks to Premium SSD V2 disks. It is not an official Microsoft product or service.
    Use of this script is at your own risk, and it is recommended to test in a non-production environment before using it in production.
    Please note that while being developed by a Microsoft employee, AzConvertV1toV2Disks.ps1 is not supported by Microsoft.
    There are none implicit or explicit obligations related to this project, it is provided 'as is' with no warranties and confer no rights.
    The author is not responsible for any issues that may arise from the use of this script.
#>

param ([string]$SubscriptionId
)
Write-Host "AzConvertV1toV2Disks Script started at $(Get-Date)" -ForegroundColor Cyan

# Create a Log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = ".\AzConvertV1toV2DisksLog_$timestamp.txt"
Start-Transcript -Path $LogFile -Append
Write-Host "AzConvertV1toV2Disks logging started to file $LogFile" -ForegroundColor Cyan

# Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Az module is not installed. Installing Az module..." -ForegroundColor Yellow
    Install-Module -Name Az -AllowClobber -Force
} else {
   Write-Host "Az module is already installed." -ForegroundColor Green
}   

# Import the Az module and check if it has imported successfully
Import-Module Az -Force
if (Get-Module -Name Az) {              
    Write-Host "Az module imported successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to import Az module. Exiting script." -ForegroundColor Red
    Stop-Transcript
    exit
}

# ---------------------------------Start of New CSV File function---------------------------------------
# Function to open a file dialog and import a CSV file
function New-CSV-File{
Add-Type -AssemblyName System.Windows.Forms

# Open file dialog
$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.Filter = "CSV files (*.csv)|*.csv"
$OpenFileDialog.Title = "Select a CSV file"
Write-Host "Opening Explorer to select a CSV file..." -ForegroundColor Green
    if ($OpenFileDialog.ShowDialog() -eq "OK") {
        $csvPath = $OpenFileDialog.FileName
        Write-Host "Importing CSV from: $csvPath"
    
        # Import the CSV
        $csvData = Import-Csv -Path $csvPath
        return $csvData
    } else {
        Write-Host "No file selected."
    }
}
# ---------------------------------- End of New-CSV-File function ----------------------------------------


# --------------------------------- Start of Convert-Disks function ---------------------------------------
function Convert-Disks {
    param ([Parameter(Mandatory = $true)][string]$diskname,[Parameter(Mandatory = $true)][string]$ResourceGroupName)

    # Check if the disk exists in the specified subscription
    $disk = Get-AzDisk -DiskName $diskname -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($disk.count -eq 0) {
        Write-Host "$diskname not found. Skipping." -ForegroundColor Yellow
        return
    }
    if ($disk.count -ne 1) {
        Write-Host "$diskname multiples found. Check inputs." -ForegroundColor Yellow
        return
    }
    
    # Begin to Convert Disks 
            $vm = Get-AzVM -ResourceGroupName $disk.ResourceGroupName -Name $disk.managedby.split('/')[-1]
            $vmname = $vm.Name
            Write-Host "Processing disk: $diskname for VMname $vmname" -ForegroundColor Cyan
            

            # Disable disk Caching if enabled (Unsupported on PremiumV2 disks)
            $cachecheck = $vm.StorageProfile.DataDisks | Where-Object { $_.Name -eq $disk.name} | Select-Object Caching
            if ($cachecheck.Caching -ne "None") {
            $setdisk = Set-AzVMDataDisk -VM $vm -Name $disk.name -Caching None
            $updatevm = Update-AzVM -VM $vm -ResourceGroupName $vm.ResourceGroupName -ErrorAction SilentlyContinue
                if ($updatevm.IsSuccessStatusCode -eq $true) {
                    Write-Host "Disk $diskname caching successfully set to None." -ForegroundColor Green
                } else {
                    Write-Host "ERROR setting caching to None for disk $diskname. Skipping disk." -ForegroundColor Red
                    return
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
                        return
                    } 
            } else{
                    Write-Host "ERROR disabling bursting on disk $diskname. Check Activity Logs. Please Note: Bursting can only be deactivated 12 hours after activation." -ForegroundColor Red
                    return  
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
                            return
                            }
                        }
                    }

            # Check if the VM is protected by Azure Backup
            # Get all Recovery Services vaults
            $vaults = Get-AzRecoveryServicesVault

            foreach ($vault in $vaults) {
                Set-AzRecoveryServicesVaultContext -Vault $vault

                # Get all containers of type AzureVM
                $containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM
                $container = $containers | Where-Object { $_.FriendlyName -eq $vmName }

                if ($container) {
                    $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM | Where-Object {
                        $_.Properties.SourceResourceId -eq $vmId
                    }

                    if ($backupItem) {
                        $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $backupItem.ProtectionPolicyName

                        $isEnhanced = $policy.PolicySubType -eq "Enhanced"

                        $backuparray += [PSCustomObject]@{
                            VMName            = $vmName
                            VaultName         = $vault.Name
                            PolicyName        = $policy.Name
                            IsEnhancedPolicy  = $isEnhanced
                            BackupManagementType        = $policy.BackupManagementType
                        }

                        break
                    }
                }
            }

            if ($backupItem) {
                Write-Host "VM '$vmName' is protected by Azure Backup with policy '$($policy.Name)' in vault '$($vault.Name)'." -ForegroundColor Cyan
                if ($isEnhanced) {
                    Write-Host "The policy is an Enhanced Backup Policy. Continuing Script" -ForegroundColor Cyan
                } else {
                    Write-Host "The policy is a Standard Backup Policy. Please convert to Enhanced Policy." -ForegroundColor Red
                    return
                    }
            }
            else{
                Write-Output "VM '$vmName' is not protected by Azure Backup. Continuing Script" -ForegroundColor Cyan
                }


            # Update the disk SKU to PremiumV2_LRS
            $diskmigration = get-azdisk $disk.Name -ResourceGroupName $disk.ResourceGroupName
            $diskconfignew = New-AzDiskUpdateConfig -skuname "PremiumV2_LRS" -BurstingEnabled $false
            $updateAzDisk = Update-AzDisk -ResourceGroupName $diskmigration.ResourceGroupName -DiskName $diskmigration.Name -Diskupdate $diskconfignew
            if ($updateAzDisk.Sku.name -eq "PremiumV2_LRS") {
                Write-Host "Successfully Converted Disk: $diskname to Premium SSD v2" -ForegroundColor Green
            } else {
                Write-Host "ERROR converting disk $diskname to Premium SSD v2. Skipping disk." -ForegroundColor Red
            return
            }
}
# ---------------------------------- End of Convert-Disks function ----------------------------------------


# --------------------------------- Start Login-to-Azure function ---------------------------------------
function Login-to-Azure {
param ([Parameter(Mandatory = $true)][string]$SubscriptionIdrun)

# Validate the SubscriptionId input format 
# This regex checks for a valid ID format, allowing for multiple IDs separated by commas
if ($SubscriptionIdrun -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(,[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})*$') {
    Write-Host "Invalid Subscription ID format. Please provide valid Subscription ID." -ForegroundColor Red
    Stop-Transcript
    exit
} else {
    Write-Host "Valid Subscription ID format detected." -ForegroundColor Cyan
}

# Check if the user is already connected to the specified subscription
$currentSubscriptionID = (Get-AzContext).Subscription.Id
if ($currentSubscriptionID -eq $SubscriptionIdrun) {
    Write-Host "Already connected to Subscription: $SubscriptionIdrun" -ForegroundColor Cyan
} else {

        # Connect to Azure Account
        $ConnectAzAccount = Connect-AzAccount -Subscription $SubscriptionIdrun -InformationAction SilentlyContinue -WarningAction SilentlyContinue
        if ($ConnectAzAccount){
            Write-Host "Successfully connected to Azure." -ForegroundColor Green
        } else {
            Write-Host "Failed to connect to Azure. Exiting script." -ForegroundColor Red
            Stop-Transcript
            exit    
        }

        # Set the subscription context
        $setazcontext = Set-AzContext -SubscriptionId $SubscriptionIdrun
        if ($setazcontext.Subscription.id -eq $SubscriptionIdrun){
            Write-Host "Successfully set context to subscription: $SubscriptionId to ensure correct Subscription selected" -ForegroundColor Green
        } else {
            Write-Host "Failed to set context to subscription: $SubscriptionIdrun. Exiting script." -ForegroundColor Red
            Stop-Transcript
            Exit
        }

        # Ensure the user has the necessary permissions to manage disks in the specified subscriptions
        $permissions = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionIdrun" | Where-Object { $_.RoleDefinitionName -eq "Contributor" -or $_.RoleDefinitionName -eq "Owner" }
        if (-not $permissions) {    
            Write-Host "You do not have the necessary permissions to manage disks in the specified subscription. Please ensure you have 'Contributor' or 'Owner' role." -ForegroundColor Red
            Stop-Transcript
            exit
        } else {
            Write-Host "You have the necessary permissions to manage disks in the specified subscription." -ForegroundColor Green
        }
    }
}
# -------------------------------- End of Login-to-Azure function ----------------------------------------


# Check if the user has provided Subscription ID
if (-not $SubscriptionId) {
    Write-Host "No Subscription ID provided. Prompting for CSV file" -ForegroundColor Cyan
    try {

        # Prompt for CSV file and sort by virtual machine unique
        $csvData = new-csv-file
        $csvData = $csvData |
        Where-Object { $_.subscriptionID -ne $null -and $_.subscriptionID -ne "" } |
        Group-Object -Property VirtualMachine |
        ForEach-Object {
            [PSCustomObject]@{
                VirtualMachine = $_.Name
                SubscriptionID = ($_.Group | Select-Object -First 1).subscriptionID
                ResourceGroup = ($_.Group | Select-Object -First 1).resourceGroup
            }
        }


       $csvcount = $csvData.Count
        if ($csvData.count -ne 0) {
            Write-Host "Successfully imported CSV data. $csvcount VM's were found. " -ForegroundColor Green
        } else {
            Write-Host "No valid Subscription ID found in the CSV file. Exiting script." -ForegroundColor Red
            Stop-Transcript
            exit
        }
    }
    catch{
        Write-Host "An error occurred while trying to prompt for a CSV file. Please ensure you have the necessary permissions." -ForegroundColor Red
        Stop-Transcript
        exit
    }
} else {
        Write-Host "Processing Specified Subscription ID: $SubscriptionId" -ForegroundColor Cyan
        $csvData = @()
        
        # Create a custom object with the provided Subscription ID
        $csvData += [PSCustomObject]@{
        SubscriptionID = $SubscriptionId    
        }
    }

# Process each row in the CSV data
foreach ($row in $csvData) {
            # Extract SubscriptionID, VirtualMachine, and ResourceGroup from the row
            $SubscriptionIdrun = $row.SubscriptionId
            $VM = $row.VirtualMachine
            $RG = $row.resourceGroup


            # Call the login function for each subscription
            try {
                login-to-azure -SubscriptionIdrun $SubscriptionIdrun
                } 
            catch {
                Write-Host "An error occurred while trying to login to Azure for Subscription ID: $SubscriptionIdrun. Please ensure you have the necessary permissions." -ForegroundColor Red
                Stop-Transcript
                exit}

              
            # Check if the VM is specified, if not, get all VMs in the subscription
                If ($VM.count -eq 0 -or $VM -eq $null) {
                    Write-Host "No Virtual Machine specified. Getting all VMs in Subscription: $SubscriptionIdrun" -ForegroundColor Cyan
                    # Get all VMs in the subscription
                    $VMs = Get-AzVM -ErrorAction SilentlyContinue
                    if ($VMs.Count -eq 0) {
                        Write-Host "No VMs found in Subscription: $SubscriptionIdrun. Exiting script." -ForegroundColor Yellow
                        Stop-Transcript
                        exit
                    }
                } else{
                    Write-Host "Getting VM: $VM in Resource Group: $RG in Subscription: $SubscriptionIdrun" -ForegroundColor Cyan
                    $VMs = Get-AzVM -ResourceGroupName $RG -Name $VM -ErrorAction SilentlyContinue 
                }

            # Build a list of VMs with disks that meet the criteria
            # Initialize an empty list to hold matching VMs
            $matchingVMs = @()
            foreach ($VM in $VMs) {
                    $ResourceGroupName = $vm.ResourceGroupName
                    $vmName = $vm.Name

                    # Combine OS and data disks
                    $allDisks = $vm.StorageProfile.DataDisks

                    foreach ($diskRef in $allDisks) {
                        $disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $diskRef.Name

                        if ($disk.DiskSizeGB -gt 512 -and $disk.OsType -eq $null -and $disk.Sku.Name -eq "Premium_LRS") {
                            $matchingVMs += $vm
                            break  # Stop checking more disks for this VM
                        }
                    }
            }

            # Starting disk conversion process
            Write-Host "Starting disk conversion in $subscriptionIdrun..." -ForegroundColor Green
            foreach ($vm in $matchingVMs){
                            #stopping VM if it is running
                            $vmname = $vm.name
                            Write-Host "Stopping VM: $vmname" -ForegroundColor Green
                            $stoppedVM = Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
                            
                            #checking VM is deallocated
                            $vmrecheck = get-azvm -status -resourcegroupname $vm.ResourceGroupName -name $vm.Name
                            if ($vmrecheck.statuses.DisplayStatus[-1] -eq "VM deallocated") {
                                    Write-Host "Successfully stopped VM: $($vm.Name)" -ForegroundColor Green
                                    $VMstopped = $true
                            } else {
                                    Write-Host "ERROR stopping VM: $($vm.Name). Skipping disk conversion." -ForegroundColor Red
                                    continue
                                    }
                            
                            # Get all data disks attached to the VM and then loop through conversion for qualifying disks
                            $allDataDisks = $vm.StorageProfile.DataDisks
                            foreach ($diskRef in $allDataDisks) {
                                $disk = Get-AzDisk -DiskName $diskRef.Name -ResourceGroupName $vm.ResourceGroupName -ErrorAction SilentlyContinue
                                if ($disk.count -eq 0) {
                                    Write-Host "Disk $diskRef Name not found in Resource Group: $vm.ResourceGroupName. Skipping disk." -ForegroundColor Yellow
                                    continue
                                }
                                
                                $diskname = $disk.name
                                if ($disk.DiskSizeGB -gt 512 -and $disk.OsType -eq $null -and $disk.Sku.Name -eq "Premium_LRS") {    
                                
                                        # Call the Convert-Disks function for disk
                                        Try {
                                            Write-Host "Converting disk: $diskname on $vmname to Premium SSD V2..." -ForegroundColor Cyan
                                            Convert-Disks -diskname $diskname -ResourceGroupName $vm.ResourceGroupName
                                        }
                                        catch {
                                            Write-Host "ERROR in Convert-Disks function for disk $diskname" -ForegroundColor Red
                                            continue
                                        }
                                } else{
                                write-host "$diskname does not meet the conversion criteria. Skipping disk." -ForegroundColor Yellow
                                continue
                                }
                            }

                            # Start the VM if it was stopped for the conversion
                            if ($vm -ne $null -and $VMstopped -eq $true) {
                                Write-Host "Starting VM: $vmname" -ForegroundColor Green
                                $startVM = Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.name
                                $vmstatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.name -Status | Where-Object {$_.Statuses.Code -eq "PowerState/running"} 
                                if($vmstatus.statuses.DisplayStatus[-1] -eq "VM running") {
                                    Write-Host "Successfully started VM: $vmname" -ForegroundColor Green
                                } else {
                                    Write-Host "ERROR starting VM: $vmname. Please check Activity Logs." -ForegroundColor Red
                                    continue
                                }
                            } else {
                            Write-Host "was not attached to any VM or VM was already deallocated. Skipping VM start." -ForegroundColor Cyan
                            }
                        }
}


# End of script
Write-Host "AzConvertV1toV2Disks Script completed at $(Get-Date)" -ForegroundColor Green
Stop-Transcript
