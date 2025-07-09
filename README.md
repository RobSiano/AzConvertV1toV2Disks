# AzConvertV1toV2Disks
 
This PowerShell Script takes Azure Subscriptions and converts Premium SSD V1 disks to Premium SSD V2 disks. It will skip all unsupported disk types such as OS disks and check for Enhanced Backup Policy if Azure Backup is enabled. It will also attempt to disable caching, bursting, and double encryption to meet migration requirements.

Modules Required:
* Microsft Az (checks and install is in code)

PowerShell Versions Tested:
* PowerShell 7.5.2

Files to Download:
* AzConvertV1toV2Disks.ps1

#Option 1: Selecting a Subscription and running all all VM's/Disks that are supported
Instructions
1. Download AzConvertV1toV2Disks.ps1

2. Go to your Azure Subscription and obtain your SubscriptionID.

3. Execute the AzConvertV1toV2Disks.ps1 script. (Recommend targeting a test environment)

The command to execute the code will be: 
.\AzConvertV1toV2Disks.ps1 -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxx"

4. Review Script Execution in terminal or log file.


##Option 2: Import a CSV file from a Resource Graph Query, export to CSV file, and then submit the Subscriptions and VM's you would like to target specifically.
Instructions
1. Open https://portal.azure.com and login.

2. Navigate to Azure Resource Graph Explorer and Input the following Query:

print(
Resources
| where type == "microsoft.compute/disks"
| extend diskState = tostring(properties.diskState)
| where not(name endswith "-ASRReplica" or name startswith "ms-asr-" or name startswith "asrseeddisk-")
| where (tags !contains "kubernetes.io-created-for-pvc") and tags !contains "ASR-ReplicaDisk" and tags !contains "asrseeddisk" and tags !contains "RSVaultBackup"
| extend props = parse_json(properties)
| extend VirtualMachine = tostring(split(managedBy, "/")[-1])
| extend SubscriptionID = tostring(split(managedBy, "/")[2])
| project
   name,
   resourceGroup,
   DiskResourceID=id,
   location,
   burstingEnabled = tostring(props.burstingEnabled),
   encryptionType = tostring(props.encryption.type),
   caching = tostring(props.diskState), // Note: caching is typically set at the VM level, not directly on the dis
   VirtualMachineResourceID=managedBy,
   VirtualMachine,
   SubscriptionID)
   
3. Select Download as CSV file and save to your local disk. (Modify the file as required to remove target VM's)

4. Download AzConvertV1toV2Disks.ps1

5. Go to your Azure Subscription and obtain your SubscriptionID.

6. Execute the AzConvertV1toV2Disks.ps1 script. (Recommend targeting a test environment)

The command to execute the code will be: 
.\AzConvertV1toV2Disks

An Explorer window will appear for you to select the .CSV file and Submit it for processing

7. Review Script Execution in terminal or log file.

Considerations:
For a more targeted approach, please consider using the CSV import Option 2 instead. Also consider re-enabling double encryption if required via code. Please read the disclaimer at the top of the AzConvertV1toV2Disks.ps1 before executing the code.
