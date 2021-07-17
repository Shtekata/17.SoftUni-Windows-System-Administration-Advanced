#
# Lab Environment for WSAA 2021.06 - M1 - HW
#

# General constants/variables
$SourceVHD = 'C:\BAK\WIN-SRV-2K19-ST-DE.vhdx'
$TargetFolder = 'C:\VM\'

# Local credentials
$Password = ConvertTo-SecureString -AsPlainText "Password1" -Force
$LocalUser = "Administrator" 
$LC = New-Object System.Management.Automation.PSCredential($LocalUser, $Password)

# Domain credentials
$Domain = "WSAA.LAB"
$DomainUser = "$Domain\Administrator" 
$DC = New-Object System.Management.Automation.PSCredential($DomainUser, $Password)

# VM Name
$VM0 = 'WSAA-M1-VM-DC'
$VM1 = 'WSAA-M1-VM-HW'

# Create Differential Disk
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VM (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 2048mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Create second disk
New-VHD -Path ($TargetFolder + $VM1 + "-DISK1.vhdx") -SizeBytes 10gb -Dynamic

# Attach the second disk
Add-VMHardDiskDrive -VMName $VM1 -Path ($TargetFolder + $VM1 + "-DISK1.vhdx")

# Create third disk 
New-VHD -Path ($TargetFolder + $VM1 + "-DISK2.vhdx")-SizeBytes 10gb -Dynamic

# Attach the third disk
Add-VMHardDiskDrive -VMName $VM1 -Path ($TargetFolder + $VM1 + "-DISK2.vhdx")

# Create fourth disk
New-VHD -Path ($TargetFolder + $VM1 + "-DISK3.vhdx")-SizeBytes 20gb -Dynamic

# Attach the fourth disk
Add-VMHardDiskDrive -VMName $VM1 -Path ($TargetFolder + $VM1 + "-DISK3.vhdx")

# Create fifth disk
New-VHD -Path ($TargetFolder + $VM1 + "-DISK4.vhdx") -SizeBytes 20gb -Dynamic

# Attach the fifth disk
Add-VMHardDiskDrive -VMName $VM1 -Path ($TargetFolder + $VM1 + "-DISK4.vhdx")

# Power on the VM
Start-VM -VMName $VM1

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.100" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

# Rename the VM
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW -Restart }

# Wait the machine to boot
pause

# Domain join
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait the machine to boot
pause

# Add second network adapter to the second machine (HW-M1/HWM2)
Add-VMNetworkAdapter -VMName $VM1 -SwitchName "vPrivate"

# Set the IP address
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.67.100" -PrefixLength 24 }

# Add second network adapter to the first machine (HW-DC/EM1)
Add-VMNetworkAdapter -VMName $VM0 -SwitchName "vPrivate"

# Set the IP address
Invoke-Command -VMName $VM0 -Credential $DC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.67.2" -PrefixLength 24 } 

#
# Next steps are expected to be executed manually
#

# Switch session to the VM
Enter-PSSession -VMName $VM1 -Credential $DC

# Set disk type of the two 10GB disks to SSD
Get-PhysicalDisk | Where DeviceID -In -Value 1,2 | Set-PhysicalDisk -MediaType SSD

# Set disk type of the two 20GB disks to HDD
Get-PhysicalDisk | Where DeviceID -In -Value 3,4 | Set-PhysicalDisk -MediaType HDD

# Create the pool
$PD = (Get-PhysicalDisk -CanPool $true); New-StoragePool -FriendlyName HomeworkPool -StorageSubsystemFriendlyName "Windows Storage*" -PhysicalDisks $PD -Verbose

# Define SSD tier
New-StorageTier -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "SSDTier" -MediaType SSD -Verbose

# Define HDD tier
New-StorageTier -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "HDDTier" -MediaType HDD -Verbose

# Create virtual hard drive 
New-Volume -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "HomeworkDisk" -AccessPath "X:" -ResiliencySettingName "Mirror" -ProvisioningType "Fixed" -StorageTiers (Get-StorageTier -FriendlyName "*SSD*"), (Get-StorageTier -FriendlyName "*HDD*") -StorageTierSizes 6gb, 16gb -FileSystem NTFS -AllocationUnitSize 64KB

# Install iSCSI Target role component
Install-WindowsFeature FS-iSCSITarget-Server

# Create iSCSI target
New-IscsiServerTarget -TargetName "homework" -InitiatorId @("IPAddress:192.168.67.2")

# Create iSCSI virtual hard disk
New-IscsiVirtualDisk -Path "X:\homework-iscsi-disk.vhdx" -Size 10GB

# Attach iSCSI virtual hard disk to an iSCSI target
Add-IscsiVirtualDiskTargetMapping -TargetName "homework" -DevicePath "X:\homework-iscsi-disk.vhdx"

# Exit PowerShell session
exit

# Establish PowerShell session to the other machine (DC in our case)
Enter-PSSession -VMName $VM0 -Credential $DC

# Start iSCSI initiator service
Start-Service msiscsi

# Set service start up type to automatic
Set-Service msiscsi -StartupType Automatic

# Create new iSCSI target portal
New-IscsiTargetPortal -TargetPortalAddress "192.168.67.100" -InitiatorPortalAddress "192.168.67.2" -InitiatorInstanceName "ROOT\ISCSIPRT\0000_0"

# Connect to an iSCSI target
$TARGET=Get-IscsiTarget
Connect-IscsiTarget -NodeAddress $TARGET.NodeAddress -TargetPortalAddress "192.168.67.100" -InitiatorPortalAddress "192.168.67.2" -IsPersistent $true

# Initialize and format the disk
Initialize-Disk -Number 1 -PartitionStyle GPT 
New-Volume -DiskNumber 1 -FriendlyName "iSCSIDisk" -FileSystem NTFS -DriveLetter S

# Create folder
New-Item -ItemType Directory -Path "S:\Shared Data"

# Set NTFS permissions
$ACL = Get-Acl -Path "S:\Shared Data"
$AR = New-Object System.Security.AccessControl.FileSystemAccessRule("WSAA\Domain Users", "Read", "Allow")
$ACL.SetAccessRule($AR)
$AR = New-Object System.Security.AccessControl.FileSystemAccessRule("WSAA\Domain Admins", "FullControl", "Allow")
$ACL.SetAccessRule($AR)
$ACL | Set-Acl -Path "S:\Shared Data"

# Share the folder
New-SmbShare -Name "Shared" -Path "S:\Shared Data" -FullAccess Everyone

# Exit PowerShell session
exit

# Done.