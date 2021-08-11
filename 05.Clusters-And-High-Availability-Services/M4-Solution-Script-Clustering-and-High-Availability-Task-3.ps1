#
# Lab Environment for WSAA 2021.06 - M4 - Task 3 - Docker
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
$VM2 = 'WSAA-M4-VM-HW31'
$VM3 = 'WSAA-M4-VM-HW32'

# Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 3072mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM3 -MemoryStartupBytes 3072mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Prepare member VMs for nested virtualization
Set-VMMemory -VMName $VM2, $VM3 -DynamicMemoryEnabled $false 
Set-VMProcessor -VMName $VM2, $VM3 -ExposeVirtualizationExtensions $true
Get-VMNetworkAdapter -VMName $VM2, $VM3 | Set-VMNetworkAdapter -MacAddressSpoofing On

# Start VMs
Start-VM -Name $VM1, $VM2, $VM3

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW43-DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW43-SRV1 -Restart  }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW43-SRV2 -Restart  }

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

# Add a DNS forwarder in DC
Invoke-Command -VMName $VM1 -Credential $DC -ScriptBlock { Add-DnsServerForwarder -IPAddress 8.8.8.8 }

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

# Role installation
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Install-WindowsFeature -Name Containers, FS-FileServer, Hyper-V -IncludeManagementTools -Restart }

# Wait for the roles to be installed on the VMs
pause

# Install Docker Provider
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; Install-Module -Name DockerMsftProvider -Repository PSGallery -Force }

# Install Docker
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Install-Package -Name Docker -ProviderName DockerMsftProvider -Force }

# Ensure the Docker service is started
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Start-Service docker }

# Add set of firewall rules to enable correct communication between nodes
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "Docker Port 2376/tcp" -Direction Inbound -LocalPort 2376 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "Docker Port 2377/tcp" -Direction Inbound -LocalPort 2377 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "Docker Port 4789/udp" -Direction Inbound -LocalPort 4789 -Protocol UDP -Action Allow }
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "Docker Port 7946/tcp" -Direction Inbound -LocalPort 7946 -Protocol TCP -Action Allow }
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { New-NetFirewallRule -DisplayName "Docker Port 7946/udp" -Direction Inbound -LocalPort 7946 -Protocol UDP -Action Allow }

# Initialize the Swarm on node #1 (SRV1)
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker swarm init --advertise-addr 192.168.99.10 ; docker swarm join-token -q worker > c:\swarm-token.txt }

# Join node #2 (SRV2) to the Swarm
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { docker swarm join --token $(type \\HW43-SRV1\c$\swarm-token.txt) 192.168.99.10:2377 }

# Check the status of the Swarm
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker node ls }