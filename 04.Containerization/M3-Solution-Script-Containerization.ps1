#
# Lab Environment for WSAA 2021.06 - M3 - Containers
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
$VM1 = 'WSAA-M3-VM-HWDC'
$VM2 = 'WSAA-M3-VM-HWS1'

# Create Differential Disks
New-VHD -Path ($TargetFolder + $VM1 + ".vhdx") -ParentPath $SourceVHD -Differencing
New-VHD -Path ($TargetFolder + $VM2 + ".vhdx") -ParentPath $SourceVHD -Differencing

# Create VMs (with automatic checkpoints turned off and no dynamic memory)
New-VM -Name $VM1 -MemoryStartupBytes 1536mb -VHDPath ($TargetFolder + $VM1 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false
New-VM -Name $VM2 -MemoryStartupBytes 3072mb -VHDPath ($TargetFolder + $VM2 + ".vhdx") -Generation 2 -SwitchName "NAT vSwitch" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

# Prepare the VM for nested virtualization
Set-VMMemory -VMName $VM2 -DynamicMemoryEnabled $false 
Set-VMProcessor -VMName $VM2 -ExposeVirtualizationExtensions $true
Get-VMNetworkAdapter -VMName $VM2 | Set-VMNetworkAdapter -MacAddressSpoofing On

# Start VMs
Start-VM -Name $VM1, $VM2

# Ensure that the Administrator password is set to the same as in the beginning of the script
pause

# Change OS name
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW3-DC -Restart  }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Rename-Computer -NewName HW3-SRV1 -Restart  }

# Wait for the machines boot
pause

# Set network settings
Invoke-Command -VMName $VM1 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.2" -PrefixLength 24 -DefaultGateway 192.168.99.1 }
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.99.10" -PrefixLength 24 -DefaultGateway 192.168.99.1 ; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.99.2 }

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

# Join other machine to the domain
Invoke-Command -VMName $VM2 -Credential $LC -ScriptBlock { Add-Computer -DomainName $args[0] -Credential $args[1] -Restart } -ArgumentList $Domain, $DC

# Wait for the VM to join to the domain
pause

# 
# Actual solution
#

# Role installation. We can go only with Containers role
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Install-WindowsFeature -Name Containers -IncludeManagementTools -Restart }

# Wait for the roles to be installed on the VMs
pause

# Install Docker Provider
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; Install-Module -Name DockerMsftProvider -Repository PSGallery -Force }

# Install Docker
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Install-Package -Name Docker -ProviderName DockerMsftProvider -Force }

# Ensure the Docker service is started
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Start-Service docker }

# Check that the Docker is working and reachable
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker version }  

# Pull the image
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker image pull mcr.microsoft.com/windows/servercore/iis }

# Start a container
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker container run -d --name web1 -p 9000:80  mcr.microsoft.com/windows/servercore/iis }

# Check if the container is running
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker container ls }

# And if yes, try to access it
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { curl http://localhost:9000 -UseBasicParsing }

# Create a folder to accommodate the custom image creation process
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { New-Item -Type Directory -Path C:\Temp } 

# Download the supporting files
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { curl -UseBasicParsing https://zahariev.pro/files/web.zip -OutFile C:\Temp\web.zip}

# Expand the compressed archive
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { Expand-Archive C:\Temp\web.zip -DestinationPath C:\Temp }

# Build the image
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker image build -t hw-iis C:\Temp }

# Check if the image has been created
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker image ls }

# Start a container out of our new image
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker container run -d --name web2 -p 8080:80 hw-iis }

# Check if the container is running
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { docker container ls }

# And if yes, try to access it
Invoke-Command -VMName $VM2 -Credential $DC -ScriptBlock { curl http://localhost:8080 -UseBasicParsing }
