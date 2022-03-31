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
    
    $maxmac = (get-vmhost | Select-Object MacAddressMaximum).tostring()
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
            xVMSwitch "Extern" {
                Name = 'Extern'
                Type = 'External'
                AllowManagementOS = $true
                NetAdapterName = Get-NetAdapter -physical -Name 'NIC1'
                Ensure = 'Present'
                DependsOn = $HyperVDependency
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
            if ($_ -like 'DC*') {
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
            if ($_ -eq "RTR-COEHODE2X") {                
                
                xVMNetworkAdapter MyVM01NIC {
                    Id         = 'WAN'
                    Name       = 'WAN'
                    SwitchName = 'Extern'
                    MacAddress = $ConfigData.Nodes.where{ $_.Name -eq $node }.macaddressex
                    VMName     = $_
                    Ensure     = 'Present'
                    Dependson  = '[xVMHyperV]RTR-COEHODE2X'
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
            VmName   = "DC1-COEHODE2X", "RTR-COEHODE2X", "DC2-COEHODE2X", "CLT-COEHODE2X"
            Role     = "VM"
        })
    Nodes       = @(@{
            Name       = 'D1-COEHODE2X'
            MacAddress = '00155D02B2FF'
                
        },
        @{
            Name       = 'DC2-COEHODE2X'
            MacAddress = '00155D02B2FE'
                
        },
        @{
            Name         = 'RTR-COEHODE2X'
            MacAddress   = '00155D02B2FD'
            MacAddressEx = '00155D02B2FC'
              
        },
        @{
            Name       = 'CLT-COEHODE2X'
            MacAddress = '00155D02B2FB'
              
        })
        
    
    NonNodeData = 
    @{
        SwitchName               = "Extern"
        SwitchNameNonPublic      = "LAB"
        StartUpMemory            = 1024Mb
        MinimumMemory            = 512Mb
        MaximumMemory            = 4096Mb
        ProcessorCount           = 2
        AutomaticSnapshotEnabled = $false
        
    } 
}


xVMHyperV_Complete -ServerBasePath "$((get-vmhost).VirtualMachinePath)\Base\ws2022_DC_DE_21-03-2022-UEFI .vhdx" -ClientBasePath "$((get-vmhost).VirtualMachinePath)\Base\W11-PRO-22-3-2022-UEFI.vhdx"  -ConfigurationData $ConfigData -OutputPath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\hyperv" -VmPath "$((get-vmhost).VirtualMachinePath)"
    
