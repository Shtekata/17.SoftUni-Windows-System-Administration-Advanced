#
# Lab Environment for WSAA 2021.06 - M7
#
# 
# Part 1 & 2
# 
# Service Center - VMM
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
$VM1 = 'WSAA-M7-VM-DC'
$VM2 = 'WSAA-M7-VM-S1-STR'
$VM3 = 'WSAA-M7-VM-S2-VMM'
$VM4 = 'WSAA-M7-VM-S3-HV1'
$VM5 = 'WSAA-M7-VM-S4-HV2'

# Option 1: Clone VHDs
# cp $SourceVHD ($TargetFolder + $VM1 + ".vhdx") 
# cp $SourceVHD ($TargetFolder + $VM2 + ".vhdx") 
# cp $SourceVHD ($TargetFolder + $VM3 + ".vhdx") 
# cp $SourceVHD ($TargetFolder + $VM4 + ".vhdx") 
# cp $SourceVHD ($TargetFolder + $VM5 + ".vhdx") 

# Option 2: Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM4 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM5 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM3 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM4 -MemoryStartupBytes 1792mb -VHDPath ($TargetFolder + $VM4 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM5 -MemoryStartupBytes 1792mb -VHDPath ($TargetFolder + $VM5 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Prepare Hyper-V VMs for nested virtualization
Set-VMProcessor -VMName $VM4, $VM5 -ExposeVirtualizationExtensions $true
Get-VMNetworkAdapter -VMName $VM4, $VM5 | Set-VMNetworkAdapter -MacAddressSpoofing On

# Create two additional disks on the STORAGE machine
New-VHD -Path ($TargetFolder + $VM2 + "-D1.vhdx") -SizeBytes 200gb -Dynamic
New-VHD -Path ($TargetFolder + $VM2 + "-D2.vhdx") -SizeBytes 100gb -Dynamic

# Attach the two additional disks to the STORAGE machine
Add-VMHardDiskDrive -VMName $VM2 -Path ($TargetFolder + $VM2 + "-D1.vhdx")
Add-VMHardDiskDrive -VMName $VM2 -Path ($TargetFolder + $VM2 + "-D2.vhdx")

# Start VMs
Start-VM -Name $VM1, $VM2, $VM3, $VM4, $VM5

# Ensure that the Administrator password is set
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName STORAGE -Restart  }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { Rename-Computer -NewName VMM -Restart  }
Invoke-Command -VMName $VM4 -Credential $LC -ScriptBlock { Rename-Computer -NewName HV1 -Restart  }
Invoke-Command -VMName $VM5 -Credential $LC -ScriptBlock { Rename-Computer -NewName HV2 -Restart  }

# Set network settings
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.2" -PrefixLength 24 -DefaultGateway 192.168.99.1 }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.3" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.10" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM4 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.21" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM5 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.22" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

# Install AD DS + DNS on the DC
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools }
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Install-ADDSForest -CreateDnsDelegation:$false -DatabasePath "C:\Windows\NTDS" -DomainMode "WinThreshold" -DomainName $args[0] -ForestMode "WinThreshold" -InstallDns:$true -LogPath "C:\Windows\NTDS" -NoRebootOnCompletion:$false -SysvolPath "C:\Windows\SYSVOL" -Force:$true -SafeModeAdministratorPassword $args[1] } -ArgumentList $Domain, $Password

# Wait for the AD to be setup
pause

# Add a DNS forwarder in DC
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Add-DnsServerForwarder -IPAddress 8.8.8.8 }

# Create a Run As Account to be used in VMM
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-ADUser -Name VMMRunAs -AccountPassword $args[0] -DisplayName "VMM Run As Account" -Enabled $true -GivenName VMM -Surname RunAs -UserPrincipalName vmmrunas@wsaa.lab ; Add-ADGroupMember "Domain Admins" VMMRunAs } -ArgumentList $Password

# Create additional user with administrative privileges
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-ADUser -Name "Admin User" -AccountPassword $args[0] -DisplayName "Admin User" -Enabled $true -GivenName Admin -Surname User -UserPrincipalName admin.user@wsaa.lab -SamAccountName admin.user ; Add-ADGroupMember "Domain Admins" admin.user } -ArgumentList $Password

# Create additional user with no administrative privileges
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { New-ADUser -Name "Regular User" -AccountPassword $args[0] -DisplayName "Regular User" -Enabled $true -GivenName Regular -Surname User -UserPrincipalName regular.user@wsaa.lab -SamAccountName regular.user } -ArgumentList $Password

# Join other machines to the domain
Invoke-Command -VMName $VM2, $VM3, $VM4, $VM5 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait for the VMs to join to the domain
pause

# Add second NIC for storage to STORAGE, HV1 and HV2
Add-VMNetworkAdapter -VMName $VM2, $VM4, $VM5 -Name "Storage NIC" -SwitchName "vStorage"

# Add third NIC for cluster communication to both HV machines
Add-VMNetworkAdapter -VMName $VM4, $VM5 -Name "Private NIC" -SwitchName "vPrivate"

# Add fourth NIC for cluster communication to both HV machines
Add-VMNetworkAdapter -VMName $VM4, $VM5 -Name "Public NIC" -SwitchName "NAT vSwitch"

# Set the IP address for the second NICs
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.97.3" -PrefixLength 24 }
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.97.21" -PrefixLength 24 }
Invoke-Command -VMName $VM5 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 2" -NewName "Storage" ; New-NetIPAddress -InterfaceAlias "Storage" -IPAddress "192.168.97.22" -PrefixLength 24 }

# Set the IP address for the third NICs
Invoke-Command -VMName $VM4 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 3" -NewName "Private" ; New-NetIPAddress -InterfaceAlias "Private" -IPAddress "192.168.98.21" -PrefixLength 24 }
Invoke-Command -VMName $VM5 -Credential $DC -ScriptBlock { Rename-NetAdapter -Name "Ethernet 3" -NewName "Private" ; New-NetIPAddress -InterfaceAlias "Private" -IPAddress "192.168.98.22" -PrefixLength 24 }

# Format the two additional disks on the STORAGE VM
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Initialize-Disk -Number 1 -PartitionStyle GPT ; New-Partition -DiskNumber 1 -DriveLetter X -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel DISK1 }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Initialize-Disk -Number 2 -PartitionStyle GPT ; New-Partition -DiskNumber 2 -DriveLetter Y -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel DISK2 } 

# Install iSCSI Target on the STORAGE VM
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Install-WindowsFeature FS-FileServer, FS-iSCSITarget-Server -IncludeManagementTools }

# Start iSCSI Initiator service on both Hyper-V VMs
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { Start-Service msiscsi ; Set-Service msiscsi -StartupType Automatic }

# Install Hyper-V role on both Hyper-V VMs
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { Install-WindowsFeature Hyper-V -IncludeManagementTools -Restart }

# Wait for the VMs to boot
pause

# Adjust firewall settings for both Hyper-V hosts
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 80/tcp" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 135/tcp" -Direction Inbound -LocalPort 135 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 139/tcp" -Direction Inbound -LocalPort 139 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 443/tcp" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 445/tcp" -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 5985/tcp" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM4, $VM5 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "HV-VMM Port 5986/tcp" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow }

pause

# 
# Part 3
# 
# + CM (CFG) + Client (CLNT)
#

# VM Names
$VM6 = 'WSAA-M7-VM-S5-CFG'
$VM7 = 'WSAA-M7-VM-S6-CLT'

# Option 1: Clone VHDs
# cp $SourceVHD ($TargetFolder + $VM6 + ".vhdx") 
# cp $SourceVHD ($TargetFolder + $VM7 + ".vhdx") 

# Option 2: Create Differential Disks
New-VHD -Path ($TargetFolder + $VM6 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM7 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM6 -MemoryStartupBytes 3072mb -VHDPath ($TargetFolder + $VM6 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM7 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM7 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Start VMs
Start-VM -Name $VM6, $VM7

# Ensure that the Administrator password is set
pause

# Change OS name
Invoke-Command -VMName $VM6 -Credential $LC -ScriptBlock { Rename-Computer -NewName CONFIGSRV -Restart  }
Invoke-Command -VMName $VM7 -Credential $LC -ScriptBlock { Rename-Computer -NewName CLIENTSRV -Restart  }

# Set network settings
Invoke-Command -VMName $VM6 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.31" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM7 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.101" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

# Join the machines to the domain
Invoke-Command -VMName $VM6, $VM7 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC
