configuration xVMHyperV_Complete
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerBasePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClientBasePath,

        [System.UInt64]
        $StartupMemory = 1024Mb,

        [System.UInt64]
        $MinimumMemory = 512Mb,

        [System.UInt64]
        $MaximumMemory = 4096Mb,

        [Parameter(Mandatory = $true)]
        [System.String]
        $VMPath,

        [ValidateSet('Off', 'Paused', 'Running')]
        [System.String]
        $State = 'Off',

        [Switch]
        $WaitForIP,

        [System.Boolean]
        $AutomaticCheckpointsEnabled
    )

    Import-DscResource -ModuleName 'xHyper-V'
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    

    Node 'Localhost'
    {
        # Logic to handle both Client and Server OS
        # Configuration needs to be compiled on target server
        $Operatingsystem = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($Operatingsystem.ProductType -eq 1) {
            # Client OS, install Hyper-V as OptionalFeature
            $HyperVDependency = '[WindowsOptionalFeature]HyperV'
            WindowsOptionalFeature HyperV {
                Ensure = 'Enable'
                Name   = 'Microsoft-Hyper-V-All'
            }
        }
        else {
            # Server OS, install HyperV as WindowsFeature
            $HyperVDependency = '[WindowsFeature]HyperV', '[WindowsFeature]HyperVPowerShell'
            WindowsFeature HyperV {
                Ensure = 'Present'
                Name   = 'Hyper-V'
            }
            WindowsFeature HyperVPowerShell {
                Ensure = 'Present'
                Name   = 'Hyper-V-PowerShell'
            }
        }

        $ConfigData.AllNodes.Where{ $_.Role -eq "VM" }.VmName | ForEach-Object {
            #Make sure that path for vhdx exists
            file $_ {
                DestinationPath = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks")
                Type            = 'Directory'
                Ensure          = 'Present'
            }
            #There is an other base vhdx for windows 10
            if ($_ -eq 'POSHCL1') {
                $diffvhddependecy = "[xVhd]$_"
                xVhd $_ {
                    Ensure     = 'Present'
                    Name       = "$_-OSDisk.vhdx"
                    Path       = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks")
                    ParentPath = $ClientBasePath
                    Generation = 'Vhdx'
                    Type       = 'Differencing'
                    DependsOn  = "[File]$_", $HyperVDependency
                }
            }
            #Windows server core
            else {
                $diffvhddependecy = "[xVhd]$_"
                xVhd $_ {
                    Ensure     = 'Present'
                    Name       = "$_-OSDisk.vhdx"
                    Path       = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks")
                    ParentPath = $ServerBasePath
                    Generation = 'Vhdx'
                    Type       = 'Differencing'
                    DependsOn  = "[File]$_", $HyperVDependency
                }
            }
            #if name like POSHDC an extra hardrive will be added
            if (($_ -like 'POSHDC*') -or ($_ -Like 'POSHMS*')) {
                xvhd "$_-Data" {
                    Ensure           = 'Present'
                    Name             = "$_-DataDisk.vhdx"
                    Path             = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks")
                    Generation       = 'Vhdx'
                    MaximumSizeBytes = 40Gb
                    DependsOn        = "[File]$_", $HyperVDependency
                }
                # Attach the VHD
                xVMHardDiskDrive "ExtraDisk-$_" {
                    VMName             = $_
                    Path               = Join-Path (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks") -ChildPath "$_-DataDisk.vhdx"
                    ControllerType     = 'SCSI'
                    ControllerLocation = 1
                    Ensure             = 'Present'
                    DependsOn          = "[xVMScsiController]$_-Controller", "[xVHD]$_-Data"
                }
                xVMScsiController "$_-Controller" {
                    Ensure           = 'Present'
                    VMName           = $_
                    ControllerNumber = 0
                    DependsOn        = "[xVMHyperV]$_"
                }
            }# End if not node3
            # Ensures a VM with all the properties
            $node = $_
            if ($_ -eq "POSHFS") {                
                
                xVMNetworkAdapter MyVM01NIC {
                    Id         = 'WAN'
                    Name       = 'WAN'
                    SwitchName = 'Default Switch'
                    MacAddress = $ConfigData.Nodes.where{ $_.Name -eq $node }.macaddressex
                    VMName     = $_
                    Ensure     = 'Present'
                    Dependson  = '[xVMHyperV]POSHFS'
                }
            }# end if node1

            xVMHyperV $_ {
                Ensure                      = 'Present'
                Name                        = "$_"
                VhdPath                     = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks\$_-OSDisk.vhdx")
                SwitchName                  = $ConfigData.NonNodeData.SwitchNameNonPublic
                State                       = $State
                Path                        = $vmPath
                Generation                  = 2
                StartupMemory               = $ConfigData.NonNodeData.StartUpMemory
                MinimumMemory               = $ConfigData.NonNodeData.MinimumMemory
                MaximumMemory               = $ConfigData.NonNodeData.MaximumMemory
                ProcessorCount              = $ConfigData.NonNodeData.ProcessorCount
                MACAddress                  = $ConfigData.Nodes.where{ $_.Name -eq $node }.macaddress
                RestartIfNeeded             = $true
                WaitForIP                   = $WaitForIP
                AutomaticCheckpointsEnabled = $ConfigData.NonNodeData.AutomaticSnapshotEnabled
                DependsOn                   = $diffvhddependecy
            }           
        }
        
    }
}

$ConfigData = @{
    AllNodes    = @(
        @{
            NodeName = "localhost"
            VmName   = "POSHDC1", "POSHDC2", "POSHFS", "POSHCL1", "POSHMS1", "POSHMS2", "POSHMS3", "POSHMS4"
            Role     = "VM"
        })
    Nodes       = @(@{
            Name       = 'POSHDC1'
            MacAddress = '001523be0c01'
                
        },
        @{
            Name       = 'POSHDC2'
            MacAddress = '001523be0c02'
                
        },
        @{
            Name         = 'POSHFS'
            MacAddress   = '001523be0c03'
            MacAddressEx = '001523be0c04'
              
        },
        @{
            Name       = 'POSHCL1'
            MacAddress = '001523be0c05'
              
        })
        
    
    NonNodeData = 
    @{
        SwitchName               = "Default Switch"
        SwitchNameNonPublic      = "LAB"
        StartUpMemory            = 1024Mb
        MinimumMemory            = 512Mb
        MaximumMemory            = 4096Mb
        ProcessorCount           = 2
        AutomaticSnapshotEnabled = $false
        
    } 
}


switch ((get-item env:computername).value) {
    'LAPTOPCOEN' { xVMHyperV_Complete -ServerBasePath "$((get-vmhost).VirtualMachinePath)\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "$((get-vmhost).VirtualMachinePath)\Base\W10_E_UEFI.vhdx"  -ConfigurationData $ConfigData -OutputPath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\hyperv" -VmPath "$((get-vmhost).VirtualMachinePath)" }
    'SURFACE' { xVMHyperV_Complete -ServerBasePath "$((get-vmhost).VirtualMachinePath)\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "$((get-vmhost).VirtualMachinePath)\Base\W10_E_UEFI.vhdx"  -ConfigurationData $ConfigData -OutputPath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\hyperv" -VmPath "$((get-vmhost).VirtualMachinePath)" }
    'COENPC' { xVMHyperV_Complete -serverbasePath "$((get-vmhost).VirtualMachinePath)\Base\WS19_SE._UEFI.vhdx" -clientbasepath "$((get-vmhost).VirtualMachinePath)\Base\W10_E_UEFI.vhdx" -ConfigurationData $ConfigData -OutputPath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\hyperv" -VmPath "$((get-vmhost).VirtualMachinePath)" }
    Default { write-host "PCName is unknown" }
}