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

        # Create new VHD
        #xVhd NewVhd
        #{
        #    Ensure           = 'Present'
        #    Name             = "$VMName-OSDisk.vhdx"
        #    Path             = $Path
        #    Generation       = 'vhdx'
        #    MaximumSizeBytes = $VhdSizeBytes
        #    DependsOn        = $HyperVDependency
        #}
        $ConfigData.AllNodes.Where{ $_.Role -eq "VM" }.VmName | ForEach-Object {
            
            file $_ {
                DestinationPath = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks")
                Type            = 'Directory'
                Ensure          = 'Present'
            }
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
            if ($_ -like 'POSHDC*') {
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
                xVMHyperV $_ {
                    Ensure                      = 'Present'
                    Name                        = "$_"
                    VhdPath                     = (join-path -Path $VmPath -ChildPath "$_\Virtual Hard Disks\$_-OSDisk.vhdx")
                    SwitchName                  = $ConfigData.NonNodeData.SwitchName
                    State                       = $State
                    Path                        = $vmPath
                    Generation                  = 2
                    StartupMemory               = $ConfigData.NonNodeData.StartUpMemory
                    MinimumMemory               = $ConfigData.NonNodeData.MinimumMemory
                    MaximumMemory               = $ConfigData.NonNodeData.MaximumMemory
                    ProcessorCount              = $ConfigData.NonNodeData.ProcessorCount
                    MACAddress                  = $ConfigData.Nodes.where{ $_.Name -eq $node }.macaddressex
                    RestartIfNeeded             = $true
                    WaitForIP                   = $WaitForIP
                    AutomaticCheckpointsEnabled = $ConfigData.NonNodeData.AutomaticSnapshotEnabled
                    DependsOn                   = $diffvhddependecy
                }
                
                xVMNetworkAdapter MyVM01NIC {
                    Id         = 'LAN'
                    Name       = 'LAN'
                    SwitchName = 'LAB'
                    MacAddress = $ConfigData.Nodes.where{ $_.Name -eq $node }.macaddress
                    VMName     = $_
                    Ensure     = 'Present'
                }
            }# end if node1
            else {
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
            }# end els node1
            
            
        }
        
    }
}

$ConfigData = @{
    AllNodes    = @(
        @{
            NodeName = "localhost"
            VmName   = "POSHDC1", "POSHDC2", "POSHFS", "POSHCL1"
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
# Save ConfigurationData in a file with .psd1 file extension
if (((get-item env:computername).value) -eq "SURFACE") {
    xVMHyperV_Complete -ServerBasePath "C:\vm\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "C:\vm\Base\W10_E_UEFI.vhdx"  -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "c:\vm"
}
else {
    #Sample_xVMHyperV_Complete -serverbasePath "D:\vm\Base\WS19_SE._UEFI.vhdx" -clientbasepath "D:\vm\Base\W10_E_UEFI.vhdx" -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "d:\vm"
}

switch ((get-item env:computername).value) {
    'LAPTOPCOEN' { xVMHyperV_Complete -ServerBasePath "Z:\VM\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "Z:\VM\Base\w10_E_1909.vhdx"  -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "z:\vm" }
    'SURFACE' { xVMHyperV_Complete -ServerBasePath "C:\vm\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "C:\vm\Base\W10_E_UEFI.vhdx"  -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "c:\vm" }
<<<<<<< HEAD
    'PSDEMO' { xVMHyperV_Complete -ServerBasePath "D:\VM\Base\WS2019_SE_UEFI.vhdx" -ClientBasePath "D:\VM\Base\w10_E_1909.vhdx"  -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "D:\vm" }
    Default {}
=======
    'COENPC' { xVMHyperV_Complete -serverbasePath "D:\vm\Base\WS19_SE._UEFI.vhdx" -clientbasepath "D:\vm\Base\W10_E_UEFI.vhdx" -ConfigurationData $ConfigData -OutputPath C:\dsc\hyperv -VmPath "d:\vm" }
    Default { write-host "PCName is unknown" }
>>>>>>> 4e12d3ea86aa2033f1f5638103f7d5299d9d1a0a
}