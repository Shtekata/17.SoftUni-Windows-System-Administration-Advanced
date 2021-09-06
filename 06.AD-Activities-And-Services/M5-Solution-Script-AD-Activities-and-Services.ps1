#
# Lab Environment for WSAA 2021.06 - M5 - Task 1 - DHCP Failover
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
$VM1 = 'WSAA-M5-VM-HWDC'
$VM2 = 'WSAA-M5-VM-HWS1'
$VM3 = 'WSAA-M5-VM-HWS2'
$VM4 = 'WSAA-M5-VM-HWS3'

# Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM4 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM3 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM4 -MemoryStartupBytes 1024mb -VHDPath ($TargetFolder + $VM4 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Start VMs
Start-VM -Name $VM1, $VM2, $VM3, $VM4

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW5-DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW5-SRV1 -Restart  }
Invoke-Command -VMName $VM3 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW5-SRV2 -Restart  }
Invoke-Command -VMName $VM4 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW5-SRV3 -Restart  }

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

# Join the other servers (SRV1, SRV2) to the domain
Invoke-Command -VMName $VM2, $VM3 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait for the VMs to join to the domain
pause

#
# Actual Solution
#

# Install DHCP role on SRV1 and SRV2
Invoke-Command -VMName $VM2, $VM3 -Credential $DC -ScriptBlock { Install-WindowsFeature DHCP -IncludeManagementTools }

# Configure DHCP service on both DHCP servers (SRV1 and SRV2)
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-DhcpServerSecurityGroup ; Restart-Service DHCPServer ; Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 2 ; Add-DhcpServerInDC -DnsName hw5-srv1.wsaa.lab -IPAddress 192.168.99.10 }
Invoke-Command -VMName $VM3 -Credential $DC -ScriptBlock { Restart-Service DHCPServer ; Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 2 ; Add-DhcpServerInDC -DnsName hw5-srv2.wsaa.lab -IPAddress 192.168.99.11 }

# Create a DHCP scope (with 2 minutes lease time for demonstration purposes) on SRV1 and set some options
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-DhcpServerv4Scope -Name "Homework" -StartRange 192.168.99.100 -EndRange 192.168.99.200 -SubnetMask 255.255.255.0 -LeaseDuration 0.0:2:0 }
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Set-DhcpServerv4OptionValue -ScopeId 192.168.99.0 -DnsServer 192.168.99.2 -DnsDomain "wsaa.lab" -Router 192.168.99.1 }

# Create a failover relationship 
# An active-active relationship
#Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-DhcpServerv4Failover -Name "DHCP-FO-AA" -PartnerServer "hw5-srv2.wsaa.lab" -ScopeId 192.168.99.0 -SharedSecret "Secret1" }

# An active-passive relationship
#Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-DhcpServerv4Failover -Name "DHCP-FO-AP" -PartnerServer "hw5-srv2.wsaa.lab" -ServerRole Standby -ScopeId 192.168.99.0 }

# An active-active relationship with load balance amount of 50%
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Add-DhcpServerv4Failover -Name "DHCP-FO-AA-LB" -PartnerServer "hw5-srv2.wsaa.lab" -ScopeId 192.168.99.0 -LoadBalancePercent 50 -MaxClientLeadTime 00:01:00 -AutoStateTransition $False }

# Obtain address on SRV3 if it doesn't have one
# Use ipconfig /all to check from which server it took the address. It should be the SRV1 (192.168.99.10)
# Either stop the DHCP service on SRV1 or change the load balance percentage to 100% for the SRV2
# Release and renew the address on SRV3. Check again which DHCP server gave it

#
# Lab Environment for WSAA 2021.06 - M5 - Task 2 - Service Account
#

# On DC create the Root Key if not created already
Add-KDSRootKey -EffectiveTime (Get-Date).AddHours(-10)

# Create the service account
New-ADServiceAccount -Name "HWService" -DNSHostName "HWService.wsaa.lab" -Enabled $True -PrincipalsAllowedToRetrieveManagedPassword HW5-SRV1$

# On SRV1 Download the service from https://zahariev.pro/files/wsaa-service.zip

# Extract the service to C:\WSAA folder

# Register the service with
New-Service -Name WSAAService -BinaryPathName C:\WSAA\WSAAService.exe

# Make sure that the C:\Temp folder is there
# Open Server Manager, navigate to Tools and click on Services
# Find the WSAAService service and double-click on it
# Switch to the Log On tab
# Make sure that the This account option is selected and click Browse
# Click on Locations button
# Select Entire Directory and click OK
# Enter HWService, click Check Names and click OK
# Clear both password related fields and click OK
# Click OK on the dialog showing that Log On As A Service right has been granted
# Start the service
# Check the C:\Temp folder for a file WSAAService.log and see what is there
