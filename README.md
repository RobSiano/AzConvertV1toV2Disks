# **AzConvertV1toV2Disks**

This PowerShell Script takes Azure Subscriptions and converts Premium SSD V1 disks to Premium SSD V2 disks. It will skip all unsupported disk types such as OS disks. It will also attempt to disable caching, bursting, and double encryption to meet migration requirements. Those features need to be disabled in order to perform the migration to Premium SSD V2. Azure Backup policies must also be on Enhanced or disabled before performing the migration, the code will check that this condition is met but will not change your backup policy or disable it. The migration path for disks that do not meet requirements involves creating snapshots and deploying new disks from snapshot which is not covered in this code.
See links below for more information. Information/Logging is collected and outputted to a text file in the same folder the script was executed in.

MS Link for reference:
https://learn.microsoft.com/en-us/azure/virtual-machines/disks-convert-types?tabs=azure-powershell

Modules Required:
* Microsoft Az (validates and installs if not detected)

PowerShell Versions Tested:
* PowerShell 7.5.2

Files to Download:
* AzConvertV1toV2Disks.ps1

----

# **Run Option 1**
**Selecting a Subscription and running all VMs/Disks that are supported:**

Instructions
1. Download **AzConvertV1toV2Disks.ps1**

2. Go to your Azure Subscription and obtain your SubscriptionID.

3. Execute the AzConvertV1toV2Disks.ps1 script using command example below. (Recommend targeting a test environment to start)

The command to execute the code will be: 
```.\AzConvertV1toV2Disks.ps1 -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxx"```

4. Review Script Execution in terminal or log file.

----

# **Run Option 2**
**Import a CSV file from a Resource Graph Query. Generate query, export to CSV file, and then submit the Subscriptions and VM's you would like to target specifically:**

Instructions
1. Open https://portal.azure.com and login.

2. Navigate to Azure Resource Graph Explorer and Input the following Query:

```sql
Resources
| where type == "microsoft.compute/disks"
| extend diskState = tostring(properties.diskState)
| where not(name endswith "-ASRReplica" or name startswith "ms-asr-" or name startswith "asrseeddisk-")
| where (tags !contains "kubernetes.io-created-for-pvc") and tags !contains "ASR-ReplicaDisk" and tags !contains "asrseeddisk" and tags !contains "RSVaultBackup"
| extend props = parse_json(properties)
| extend VirtualMachine = tostring(split(managedBy, "/")[-1])
| extend SubscriptionID = tostring(split(managedBy, "/")[2])
| project
   Name,
   ResourceGroup,
   DiskResourceID=id,
   Location,
   BurstingEnabled = tostring(props.burstingEnabled),
   EncryptionType = tostring(props.encryption.type),
   Caching = tostring(props.diskState), // Note: caching is typically set at the VM level, not directly on the dis
   VirtualMachineResourceID=managedBy,
   VirtualMachine,
   SubscriptionID
```
   
3. Select Download as CSV file and save to your local disk. (Modify the file as required to remove target VM's. The 3 required columns are SubscriptionID, VirtualMachine, and ResourceGroup)

4. Download **AzConvertV1toV2Disks.ps1**

5. Go to your Azure Subscription and obtain your SubscriptionID.

6. Execute the AzConvertV1toV2Disks.ps1 script. (Recommend targeting a test environment to start)

The command to execute the code will be: 
```.\AzConvertV1toV2Disks```

An Explorer window will appear for you to select the .CSV file and Submit it for processing

7. Review Script Execution in terminal or log file.

**Important Considerations:**
For a more targeted approach, please consider using the CSV import Option 2 instead. Also consider re-enabling double encryption if required. If Azure Backup is enabled with an older policy then you will need to manually migrate to Enhanced policy or it will skip the VM. Please read the disclaimer at the top of the AzConvertV1toV2Disks.ps1 or below before executing the code and validate by testing in non-production environment.

---
    DISCLAIMER
    This script is provided as a personal/community tool to assist with the conversion of Azure Premium SSD V1 disks to Premium SSD V2 disks. It is not an official Microsoft product or service.
    Use of this script is at your own risk, and it is recommended to test in a non-production environment before using it in production.
    Please note that while being developed by a Microsoft employee, AzConvertV1toV2Disks.ps1 is not supported by Microsoft.
    There are none implicit or explicit obligations related to this project, it is provided 'as is' with no warranties and confer no rights.
    The author is not responsible for any issues that may arise from the use of this code.
    

