# AzConvertV1toV2Disks
 
This PowerShell Script takes Azure Subscriptions and converts Premium SSD V1 disks to Premium SSD V2 disks. It will skip all unsupported disk types such as OS disks. It will also attempt to disable caching, bursting, and double encryption to meet migration requirements.

Modules Required:
Microsft Az (checks and install is in code)

PowerShell Versions Tested:
* PowerShell 7.5.2

Files to Download:
* AzConvertV1toV2Disks.ps1

Instructions
1. Download AzConvertV1toV2Disks.ps1

2. Go to your Azure Subscription and obtain your SubscriptionID.

3. Execute the AzConvertV1toV2Disks.ps1 script. (Recommend targeting a test environment)

The command to execute the code will be: 
.\AzConvertV1toV2Disks.ps1 -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxx"

4. Review Script Execution.

Considerations:
For a more targeted approach, please consider using a resource graph query to search for qualifying disks and then modifying this code to take in a .CSV file as an input instead. You would then loop through each line sorted by subscription to target only the disks you prefer to upgrade. Also consider re-enabling double encryption if required via code. Please read the disclaimer at the top of the AzConvertV1toV2Disks.ps1 before executing the code.
