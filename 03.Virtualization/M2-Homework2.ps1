$Domain = "WSAA.LAB"
$DomainUser = "$Domain\Administrator" 
$Password = ConvertTo-SecureString -AsPlainText "Password1" -Force
$DC = New-Object System.Management.Automation.PSCredential($DomainUser, $Password)
$VM2 = 'WSAA-M2-VM-S1'

$s = New-PSSession -VMName $VM2 -Credential $DC

Invoke-Command -Session $s -Scriptblock{
$TargetFolder = 'C:\VM\'
$SourceLinuxVHD = 'C:\BAK\ALP-WEB.vhdx'
$VM3 = 'WSAA-M2-VM-Linux'

New-VHD -Path ($TargetFolder + $VM3 + ".vhdx") -ParentPath $SourceLinuxVHD -Differencing

New-VM -Name $VM3 -MemoryStartupBytes 256mb -VHDPath ($TargetFolder + $VM3 + ".vhdx") -Generation 1 -SwitchName "vExternal" | Set-VM -CheckpointType Production -AutomaticCheckpointsEnabled $false -PassThru | Set-VMMemory -DynamicMemoryEnabled $false

Start-VM -Name $VM3}

Remove-PSSession $s

