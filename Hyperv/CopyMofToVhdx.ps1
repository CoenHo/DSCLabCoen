Start-DscConfiguration -Wait -Force -Path C:\dsc\hyperv

$modules = @('ActiveDirectoryDsc', 'ComputerManagementDsc', 'NetworkingDsc', 'xDhcpServer', 'StorageDSC', 'Mario_cVSS', 'DFSDsc', 'FileSystemDsc')

foreach ($module in $modules) {
    if (-not(test-path "C:\Program Files\WindowsPowerShell\Modules\$module")) {
        install-module $module -force
    }
}

$vms = get-vm posh*

ForEach ($vm in $vms) {
        
        
    $VhdxPath = ($vm.HardDrives | Where-Object { $_.ControllerLocation -eq 0 }).path
            
    $Driveletter = "$((Mount-VHD $vhdxpath -Passthru | Get-Disk | Get-Partition | where-object{$_.Type -eq "Basic" }).DriveLetter):"
    $path
    if (((get-item env:computername).value) -eq "SURFACE") {
        $path = "C:\Users\coen\OneDrive\scripts\DSC\TestDsc\test"
    }
    else {
        $path = "C:\Users\chodz\OneDrive\scripts\DSC\TestDsc\test"
    }
    $path = "C:\Users\chodz\Documenten\GitHub\DSCLabCoen\test"
    copy-item -Path "$path\$($vm.name).mof" -Destination "$Driveletter\Windows\system32\Configuration\pending.mof"
    copy-item -Path "$path\$($vm.name).meta.mof" -Destination "$Driveletter\Windows\system32\Configuration\MetaConfig.mof"
    foreach ($module in $modules) {
        copy-item  "C:\Program Files\WindowsPowerShell\Modules\$module" -Destination "$Driveletter\Program Files\WindowsPowerShell\Modules\$module" -Recurse
    }
    Dismount-VHD -Path $VhdxPath
    #start-vm $vm.name
    #vmconnect localhost $vm.name    
}#End foreach