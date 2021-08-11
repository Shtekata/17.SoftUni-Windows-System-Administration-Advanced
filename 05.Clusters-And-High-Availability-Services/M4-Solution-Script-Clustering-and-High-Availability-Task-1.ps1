#
# Lab Environment for WSAA 2021.06 - M4 - Task 1 - NLB
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
$VM2 = 'WSAA-M4-VM-HW11'
$VM3 = 'WSAA-M4-VM-HW12'

# Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM3 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Start VMs
Start-VM -Name $VM1, $VM2, $VM3

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW41-DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW41-SRV1 -Restart  }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW41-SRV2 -Restart  }

# Ensure that machines are up
pause

# Set network settings
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.2" -PrefixLength 24 -DefaultGateway 192.168.99.1 }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.10" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.11" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

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
Invoke-Command -VMName $VM2, $VM3 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait for the VMs to join to the domain
pause

# 
# Actual solution
#

# Add second NIC to both SRV1 and SRV2
Add-VMNetworkAdapter -VMName $VM2, $VM3 -SwitchName "NAT vSwitch" -Passthru | Set-VMNetworkAdapter -MacAddressSpoofing On

# Set the IP address for the second NICs
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.99.110" -PrefixLength 24 }
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.99.111" -PrefixLength 24 }
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Set-NetIPInterface -InterfaceAlias "Ethernet 2" -AddressFamily IPv4 -Forwarding Enabled }

# Install NLB feature + IIS Role on member VMs
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Install-WindowsFeature NLB, Web-Server -IncludeManagementTools }

# Set customized web pages on each NLB VM
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Set-Content -Path C:\inetpub\wwwroot\index.html -Value "<h1>Hello world!</h1><br /><br /><i>Served by $(hostname)</i>" -Force }

# Configure the NLB cluster
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-NlbCluster -InterfaceName "Ethernet 2" -OperationMode Unicast -ClusterPrimaryIP 192.168.99.100 -ClusterName NLBCluster }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-NlbClusterNode -InterfaceName "Ethernet 2" -NewNodeName "HW41-SRV2" -NewNodeInterface "Ethernet 2" }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Get-NlbClusterPortRule | Set-NlbClusterPortRule -NewProtocol Tcp -NewStartPort 80 -NewEndPort 80 -NewMode Multiple -NewAffinity None }

# Add a DNS record
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Add-DNSServerResourceRecordA -ZoneName WSAA.LAB -Name web -Ipv4Address 192.168.99.100 }

# Log on to the DC, open a browser and navigate to http://web.wsaa.lab and refresh a few times