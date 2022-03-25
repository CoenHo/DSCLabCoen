$modules = @('ActiveDirectoryDsc', 'ComputerManagementDsc', 'NetworkingDsc', 'xDhcpServer', 'StorageDSC', 'Mario_cVSS', 'DFSDsc', 'FileSystemDsc', 'cNtfsAccessControl','cChoco','xRemoteDesktopAdmin')

$cred = get-credential Administrator
$s = new-psesssion -Computername 192.168.2.178 -Credential $cred
foreach ($module in $modules) {
    copy-item -ToSession $s "C:\Program Files\WindowsPowerShell\Modules\$module" -Destination "c:\Program Files\WindowsPowerShell\Modules\$module" -Recurse
}