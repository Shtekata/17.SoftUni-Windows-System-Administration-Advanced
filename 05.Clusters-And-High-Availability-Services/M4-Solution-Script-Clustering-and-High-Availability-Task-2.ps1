#
# Lab Environment for WSAA 2021.06 - M4 - Task 2 - WFC
#

# 
# Preparation
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

# VM Names
$VM1 = 'WSAA-M4-VM-DC'
$VM2 = 'WSAA-M4-VM-HW21'
$VM3 = 'WSAA-M4-VM-HW22'
$VM4 = 'WSAA-M4-VM-HW23'

# Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM4 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM3 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM4 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM4 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Start VMs
Start-VM -Name $VM1, $VM2, $VM3, $VM4

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW42-DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW42-SRV1 -Restart  }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW42-SRV2 -Restart  }
Invoke-Command -VMName $VM4 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW42-SRV3 -Restart  }

# Ensure that machines are up
pause

# Set network settings
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.2" -PrefixLength 24 -DefaultGateway 192.168.99.1 }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.10" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.11" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM4 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.12" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

# Install AD DS + DNS on the DC
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools }
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Install-ADDSForest -CreateDnsDelegation:$false -DatabasePath "C:\Windows\NTDS" -DomainMode "WinThreshold" -DomainName $args[0] -ForestMode "WinThreshold" -InstallDns:$true -LogPath "C:\Windows\NTDS" -NoRebootOnCompletion:$false -SysvolPath "C:\Windows\SYSVOL" -Force:$true -SafeModeAdministratorPassword $args[1] } -ArgumentList $Domain, $Password

# Wait for the AD to be setup
pause

# Create additional user with administrative privileges
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-ADUser -Name "Admin User" -AccountPassword $args[0] -DisplayName "Admin User" -Enabled $true -GivenName Admin -Surname User -UserPrincipalName admin.user@wsaa.lab -SamAccountName admin.user ; Add-ADGroupMember "Domain Admins" admin.user } -ArgumentList $Password

# Create additional user with no administrative privileges
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-ADUser -Name "Regular User" -AccountPassword $args[0] -DisplayName "Regular User" -Enabled $true -GivenName Regular -Surname User -UserPrincipalName regular.user@wsaa.lab -SamAccountName regular.user } -ArgumentList $Password

# Join other machines to the domain
Invoke-Command -VMName $VM2, $VM3, $VM4 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait for the VMs to join to the domain
pause

# 
# Actual solution
#

# Add second NIC for storage to all VMs
Add-VMNetworkAdapter -VMName $VM1, $VM2, $VM3, $VM4 -SwitchName "vStorage"

# Add third NIC for cluster communication to all member servers
Add-VMNetworkAdapter -VMName $VM2, $VM3, $VM4 -SwitchName "vPrivate"

# Set the IP address for the second NICs
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.77.2" -PrefixLength 24 }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.77.10" -PrefixLength 24 }
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.77.11" -PrefixLength 24 }
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.77.12" -PrefixLength 24 }

# Set the IP address for the third NICs
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 3" -NewName "Private" ; New-NetIPAddress -InterfaceAlias "Private" -IPAddress "192.168.78.10" -PrefixLength 24 }
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 3" -NewName "Private" ; New-NetIPAddress -InterfaceAlias "Private" -IPAddress "192.168.78.11" -PrefixLength 24 }
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 3" -NewName "Private" ; New-NetIPAddress -InterfaceAlias "Private" -IPAddress "192.168.78.12" -PrefixLength 24 }

# Install iSCSI Target
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Install-WindowsFeature FS-iSCSITarget-Server }

# Create iSCSI virtual hard disk (quorum)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-IscsiVirtualDisk -Path "C:\iscsi-disk-quorum.vhdx" -Size 1GB }

# Create iSCSI target (quorum)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-IscsiServerTarget -TargetName "quorum" -InitiatorId @("IPAddress:192.168.77.10", "IPAddress:192.168.77.11", "IPAddress:192.168.77.12") }

# Attach iSCSI virtual hard disk to an iSCSI target (quorum)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Add-IscsiVirtualDiskTargetMapping -TargetName "quorum" -DevicePath "C:\iscsi-disk-quorum.vhdx" }

# Create iSCSI virtual hard disk (storage)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-IscsiVirtualDisk -Path "C:\iscsi-disk-storage.vhdx" -Size 5GB }

# Create iSCSI target (storage)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-IscsiServerTarget -TargetName "storage" -InitiatorId @("IPAddress:192.168.77.10", "IPAddress:192.168.77.11", "IPAddress:192.168.77.12") }

# Attach iSCSI virtual hard disk to an iSCSI target (storage)
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Add-IscsiVirtualDiskTargetMapping -TargetName "storage" -DevicePath "C:\iscsi-disk-storage.vhdx" }

# Start iSCSI Initiator service on all member VMs
Invoke-Command -VMName $VM2, $VM3, $VM4 -Credential $DC -ScriptBlock { Start-Service msiscsi ; Set-Service msiscsi -StartupType Automatic }

# Work out iSCSI targets on member #1
# Create new iSCSI target portal
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-IscsiTargetPortal -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.10" -InitiatorInstanceName "ROOT\ISCSIPRT\0000_0" }

# Connect to an iSCSI target
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Get-IscsiTarget | foreach { Connect-IscsiTarget -NodeAddress $_.NodeAddress -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.10" -IsPersistent $true } }

# Initialize and format the disks
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Initialize-Disk -Number 1 -PartitionStyle GPT ; New-Volume -DiskNumber 1 -FriendlyName "iSCSIDiskQuorum" -FileSystem NTFS -DriveLetter Q }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Initialize-Disk -Number 2 -PartitionStyle GPT ; New-Volume -DiskNumber 2 -FriendlyName "iSCSIDiskStorage" -FileSystem NTFS -DriveLetter S }

# Work out iSCSI targets on member #2
# Create new iSCSI target portal
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { New-IscsiTargetPortal -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.11" -InitiatorInstanceName "ROOT\ISCSIPRT\0000_0" }

# Connect to an iSCSI target
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { Get-IscsiTarget | foreach { Connect-IscsiTarget -NodeAddress $_.NodeAddress -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.11" -IsPersistent $true } }

# Work out iSCSI targets on member #3
# Create new iSCSI target portal
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { New-IscsiTargetPortal -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.12" -InitiatorInstanceName "ROOT\ISCSIPRT\0000_0" }

# Connect to an iSCSI target
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { Get-IscsiTarget | foreach { Connect-IscsiTarget -NodeAddress $_.NodeAddress -TargetPortalAddress "192.168.77.2" -InitiatorPortalAddress "192.168.77.12" -IsPersistent $true } }

# Install failover role + file server role on all member VMs
Invoke-Command -VMName $VM2, $VM3, $VM4 -Credential $DC -ScriptBlock { Install-WindowsFeature FS-FileServer, Failover-Clustering -IncludeManagementTools -Restart }

# Wait for all member servers to reboot
pause

# Test cluster - optional step
# Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Test-Cluster -Node HW42-SRV1, HW42-SRV2, HW42-SRV3 }

# Create the cluster
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-Cluster -Name ClusterHW -Node HW42-SRV1, HW42-SRV2, HW42-SRV3 -StaticAddress 192.168.99.33 -NoStorage }

# Add quorum disk
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { $DQ = Get-ClusterAvailableDisk | Where -Property Size -Eq 1GB ; $DQ | Add-ClusterDisk ; Set-ClusterQuorum -DiskWitness $DQ.Name }

# Add shared volume to the cluster
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { $DS = Get-ClusterAvailableDisk | Where -Property Size -Eq 5GB ; $DS | Add-ClusterDisk ; Add-ClusterSharedVolume $DS.Name }

# Add scale out file server role
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-ClusterScaleOutFileServerRole }

# Prepare and share the folder
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-Item -Path C:\ClusterStorage\Volume1\Shares\DATA -Type Directory -Force }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-SmbShare -Name "DATA" -Path "C:\ClusterStorage\Volume1\Shares\DATA" -FullAccess Everyone }

# Log on to the HW32-SRV1 machine, open Failover Cluster Manager and examine the result

