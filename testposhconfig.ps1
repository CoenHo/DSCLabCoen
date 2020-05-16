Configuration TestDSC
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration, ComputerManagementDsc, ActiveDirectoryDSC, NetworkingDsc, xDHCPServer, StorageDSC, Mario_cVSS, FileSystemDsc

    $Secure = ConvertTo-SecureString -String "$($ConfigurationData.Credential.LabPassword)" -AsPlainText -Force
    $credential = New-Object -typename Pscredential -ArgumentList Administrator, $secure
    $DCData = $ConfigurationData.DCData
    $DHCPData = $ConfigurationData.DHCPData
    $DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("$($dcdata.DomainName)\$($Credential.UserName)", $Credential.Password)
    #Settings for all nodes
    node $AllNodes.Where{ $true }.NodeName
    {
        
        #region LCM configuration

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true
            AllowModuleOverwrite = $true
            ConfigurationMode    = 'ApplyOnly'
        }

        #endregion
        
        User AdminPassword {
            UserName             = 'Administrator'
            Password             = $Credential
            PasswordNeverExpires = $true
        }
        TimeZone ChangeToEurope {
            IsSingleInstance = 'Yes'
            TimeZone         = 'W. Europe Standard Time'
        }
        NetAdapterName RenameLanAdapter {
            NewName    = 'LAB'
            MacAddress = "$($node.MacAddress)".insert(2, "-").insert(5, "-").insert(8, "-").insert(11, "-").insert(14, "-")
        }
        
        if ($node.Nodename -eq 'POSHFS') {
            NetAdapterName RenameWanAdapter {
                NewName    = 'WAN'
                MacAddress = "$($node.MacAddressex)".insert(2, "-").insert(5, "-").insert(8, "-").insert(11, "-").insert(14, "-")
            }
        }
        If (-not [System.String]::IsNullOrEmpty($node.IPAddress)) {
            IPAddress 'PrimaryIPAddress' {
                IPAddress      = $node.IPAddress
                InterfaceAlias = $node.InterfaceAlias
                AddressFamily  = $node.AddressFamily
                DependsOn      = '[NetAdapterName]RenameLanAdapter'
            }
        }
        If (-not [System.String]::IsNullOrEmpty($node.DefaultGateway)) {
            if (($node.Nodename) -ne 'POSHFS') {
                DefaultGatewayAddress 'PrimaryDefaultGateway' {
                    InterfaceAlias = $node.InterfaceAlias
                    Address        = $node.DefaultGateway
                    AddressFamily  = $node.AddressFamily
                }
            }
        }
        If (-not [System.String]::IsNullOrEmpty($node.DnsServerAddress)) {
            DnsServerAddress 'PrimaryDNSClient' {
                Address        = $node.DnsServerAddress
                InterfaceAlias = $node.InterfaceAlias
                AddressFamily  = $node.AddressFamily
            }
        }

        #region Firewall Rules

        
        $FireWallRules = $ConfigurationData.Firewall.FirewallRuleNames

        foreach ($Rule in $FireWallRules) {
            Firewall $Rule {
                Name    = $Rule
                Enabled = 'True'
            }
        } #End foreach

        #endregion
        

    }#end allnodes

    #Region FirstDC
    
    node $AllNodes.Where{ $_.Role -eq 'FirstDC' }.NodeName
    {
        Computer $Node.NodeName {
                
            Name = $Node.NodeName
            
        }
        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'POSHDC1' }).Features) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;

            }
        } #End foreach

        WaitForADDomain 'DscForestWait' {
            DomainName = $DCData.DomainName
        }#end wait

        ADDomain 'FirstDC' {
            DomainName                    = $DCData.DomainName
            Credential                    = $Credential
            SafemodeAdministratorPassword = $Credential
            DatabasePath                  = $DCData.DCDatabasePath
            LogPath                       = $DCData.DCLogPath
            SysvolPath                    = $DCData.SysvolPath
            DependsOn                     = "[WindowsFeature]ADDomainServices"
        }#end create domain
        #Add OU, Groups, and Users
        $OUs = (Get-Content $PSScriptRoot\AD-OU.json | ConvertFrom-Json)
        $Users = (Get-Content $PSScriptRoot\AD-Users.json | ConvertFrom-Json)
        $groups = (Get-Content $PSScriptRoot\AD-group.json | ConvertFrom-Json)
        
         

        ADOrganizationalUnit $DCData.ou {
            Path                            = $($dcdata.DomainDN)
            Name                            = $dcdata.ou
            Description                     = $dcdata.ou
            ProtectedFromAccidentalDeletion = $False
            Ensure                          = "Present"
            DependsOn                       = '[ADDomain]FirstDC'
        }
        ADOrganizationalUnit 'Marketing' {
            Path                            = "ou=$($dcdata.ou),$($dcdata.DomainDN)"
            Name                            = 'Marketing'
            Description                     = 'Marketing'
            ProtectedFromAccidentalDeletion = $False
            Ensure                          = "Present"
            DependsOn                       = '[ADDomain]FirstDC'
        }
        foreach ($OU in $OUs) {
            if (($ou.name) -like "*koop") {
                ADOrganizationalUnit $OU.Name {
                    Path                            = "OU=Marketing,OU=$($dcdata.ou),$($dcdata.DomainDN)"
                    Name                            = $OU.Name
                    Description                     = $OU.Description
                    ProtectedFromAccidentalDeletion = $False
                    Ensure                          = "Present"
                    DependsOn                       = '[ADDomain]FirstDC'
                } #ou
            } #end if
            else {
                ADOrganizationalUnit $OU.Name {
                    Path                            = "OU=$($dcdata.ou),$($dcdata.DomainDN)"
                    Name                            = $OU.Name
                    Description                     = $OU.Description
                    ProtectedFromAccidentalDeletion = $False
                    Ensure                          = "Present"
                    DependsOn                       = '[ADDomain]FirstDC'
                }
            }#end if else
        } #OU

        foreach ($user in $Users) {
         
            ADUser $user.account {
                Ensure                 = "Present"
                Path                   = "$(if(($User.afdeling) -like "*koop"){"OU=$($user.afdeling),OU=Marketing"}else{"OU=$($user.Afdeling)"}),OU=$($dcdata.ou),$($dcdata.DomainDN)"
                DomainName             = $DCData.DomainName
                Username               = $user.account
                GivenName              = $user.voornaam
                Surname                = $user.achternaam
                DisplayName            = "$($user.voornaam) $($user.achternaam)" 
                Description            = $user.beschrijving
                Department             = $User.afdeling
                Enabled                = $true
                Password               = $DomainCredential
                Credential             = $DomainCredential
                PasswordNeverExpires   = $True
                DependsOn              = '[ADDomain]FirstDC'
                PasswordAuthentication = 'Negotiate'
            }
        } #user

        #region groups
        Foreach ($group in $groups) {
           ADgroup $group.name {
                    Path       = $group.DistinguishedName
                    GroupName  = $group.name
                    Category   = $group.GroupCategory
                    GroupScope = $group.GroupScope
                    DependsOn  = '[ADDomain]FirstDC'
                    Members    = $group.Members
                    ManagedBy = $group.Manager
                }
        }# end region groups
        ADGroup DomainAdmin {
            GroupName        = 'Domain Admins'
            MembersToInclude = 'Automatisering'
            DependsOn        = if (($ou.name) -eq 'Automatisering') { "[ADGroup]$($ou.name)" }
        }
        ADGroup EnterpriseAdmin {
            GroupName        = 'Enterprise Admins'
            MembersToInclude = 'Automatisering'
            DependsOn        = if (($ou.name) -eq 'Automatisering') { "[ADGroup]$($ou.name)" }
        }
        ADGroup Admin {
            GroupName        = 'Administrators'
            MembersToInclude = 'Automatisering'
            DependsOn        = if (($ou.name) -eq 'Automatisering') { "[ADGroup]$($ou.name)" }
        }
        
    }#End Region firstdc
    
    
    #region SecondDC
    node $AllNodes.Where{ $_.Role -eq 'SecondDC' }.NodeName
    {
        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'POSHDC2' }).Features) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
            }
        } #End foreach
        WaitForADDomain DscForestWait {
            DomainName   = $DCData.DomainName
            Credential   = $DomainCredential
            RestartCount = '20'
            WaitTimeout  = '600'
        }
        Computer JoinDC {
            Name       = $Node.NodeName
            DomainName = $DCData.DomainName
            Credential = $DomainCredential
            DependsOn  = '[WaitForADDomain]DSCForestWait'
        }

        ADDomainController SecondaryDC {
            DomainName                    = $DCData.DomainName
            Credential                    = $DomainCredential
            SafemodeAdministratorPassword = $DomainCredential
            DatabasePath                  = 'C:\NTDS'
            LogPath                       = 'C:\NTDS'
            DependsOn                     = @('[WindowsFeature]ADDomainServices', '[Computer]JoinDC')
        }
    }# End region secondDC

    #Region FS
    node $AllNodes.Where{ $_.Role -eq 'ROUTING' }.NodeName
    {
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'POSHFS' }).Features) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
            }
        }# End foreach

        Script 'Routing'
        {
            SetScript = {powershell.exe c:\ConfigFiles\Routing.ps1}
            TestScript = {$false}
            GetScript = { <# Do Nothing #> }
            DependsOn  = '[Windowsfeature]Routing'
        }
    }# End region FS

    #Region Client
    node $AllNodes.Where{ $_.Role -eq 'CLIENT' }.NodeName
    {
        PowerShellExecutionPolicy client {
            ExecutionPolicyScope = 'Localmachine'
            ExecutionPolicy      = 'Remotesigned'
        }
       # Adds RSAT which is now a Windows Capability in Windows 10    
            Script RSAT {
                TestScript = {
                    $packages = Get-WindowsCapability -online -Name Rsat*
                    if ($packages.state -match "Installed") {
                        Return $True
                    }
                    else {
                        Return $False
                    }
                }
    
                GetScript  = {
                    $packages = Get-WindowsCapability -online -Name Rsat* | Select-Object Displayname, State
                    $installed = $packages.Where( { $_.state -eq "Installed" })
                    Return @{Result = "$($installed.count)/$($packages.count) RSAT features installed" }
                }
    
                SetScript  = {
                    Get-WindowsCapability -online -Name Rsat* | Where-Object { $_.state -ne "installed" } | Add-WindowsCapability -online
                }
            }
    
            #since RSAT is added to the client go ahead and create a Scripts folder
            File scripts {
                DestinationPath = 'C:\Scripts'
                Ensure          = 'present'
                type            = 'directory'
            }
    }# End region Client

    #region DomainJoin config
    node $AllNodes.Where( { $_.Role -eq 'domainJoin' }).NodeName {

        

        WaitForADDomain DscForestWait {
            DomainName   = $DCData.DomainName
            Credential   = $DomainCredential
            RestartCount = '20'
            WaitTimeout  = '600'
        }

        Computer JoinDC {
            Name       = $Node.NodeName
            DomainName = $DCData.DomainName
            Credential = $DomainCredential
            DependsOn  = '[WaitForADDomain]DSCForestWait'
        }
    }#end DomainJoin Config
    
    node $AllNodes.Where( { $_.Role -eq 'ExtraHdd' }).NodeName {
        WaitForDisk Disk1 {
            DiskId           = 1
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk XVolume {
            DiskId      = 1
            DriveLetter = 'X'
            Size        = 20GB
            FSLabel     = 'Shares'
            DependsOn   = '[WaitForDisk]Disk1'
        }

        Disk ZVolume {
            DiskId      = 1
            DriveLetter = 'Z'
            FSLabel     = 'Data'
            DependsOn   = '[Disk]XVolume'
        }

        file 'eerste' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Eerste'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        file 'tweede' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Tweede'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        file 'home' {
            Type            = 'Directory'
            DestinationPath = 'z:\Users\Home'
            Ensure          = "Present"
            DependsOn       = '[Disk]ZVolume'
        }
        file 'profile' {
            Type            = 'Directory'
            DestinationPath = 'z:\Users\Profiles'
            Ensure          = "Present"
            DependsOn       = '[Disk]ZVolume'
        }

        file 'Directie' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\staf\Directie'
            Ensure          = "Present"
            DependsOn       = '[file]staf'
        }
        FileSystemAccessRule 'AddRightChangeDirectie' {
            Path     = 'x:\data\eerste\Directie'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightChangeDirectie1' {
            Path     = 'x:\data\eerste\Directie'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightChangeDirectie2' {
            Path     = 'x:\data\eerste\Directie'
            Identity = "$($dcdata.NetbiosName)\Administratie"
            Rights   = @('Read')
        }
        
        file 'staf' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\Staf'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightChangeStaf' {
            Path     = 'x:\data\eerste\Staf'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightChangeStaf1' {
            Path     = 'x:\data\eerste\Staf'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('ChangePermissions')
        }
        
        file 'administratie' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\Administratie'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightChangeAdministratie' {
            Path     = 'x:\data\eerste\Administratie'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightReadAdministratie' {
            Path     = 'x:\data\eerste\Administratie'
            Identity = "$($dcdata.NetbiosName)\Administratie"
            Rights   = @('Read')
        }

        file 'Automatisering' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\Automatisering'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightFullControlAutomatisering' {
            Path     = 'x:\data\eerste\Automatisering'
            Identity = "$($dcdata.NetbiosName)\Automatisering"
            Rights   = @('FullControl')
        }
        file 'Software' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\Software'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightReadSoftware1' {
            Path     = 'x:\data\eerste\Software'
            Identity = "$($dcdata.NetbiosName)\Automatisering"
            Rights   = @('FullControl')
        }
        FileSystemAccessRule 'AddRightChangeSoftware' {
            Path     = 'x:\data\eerste\Software'
            Identity = "$($dcdata.NetbiosName)\Domain Users"
            Rights   = @('Read')
        }
        file 'Verkoop' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Tweede\Verkoop'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightReadVerkoop2' {
            Path     = 'x:\data\eerste\Verkoop'
            Identity = "$($dcdata.NetbiosName)\Verkoop"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightChangeVerkoop' {
            Path     = 'x:\data\eerste\Verkoop'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightChangeVerkoop1' {
            Path     = 'x:\data\eerste\Verkoop'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('Read')
        }
        file 'productie' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Tweede\Productie'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightChangeProductie' {
            Path     = 'x:\data\eerste\Productie'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightChangeProductie1' {
            Path     = 'x:\data\eerste\Productie'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightReadProductie2' {
            Path     = 'x:\data\eerste\Productie'
            Identity = "$($dcdata.NetbiosName)\Productie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightFullControlProductie3' {
            Path     = 'x:\data\eerste\Productie'
            Identity = "$($dcdata.NetbiosName)\Fabricage"
            Rights   = @('Read')
        }
        file 'fabricage' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Tweede\Productie\Fabricage'
            Ensure          = "Present"
            DependsOn       = '[file]productie'
        }
        FileSystemAccessRule 'AddRightChangeFabricage' {
            Path     = 'x:\data\eerste\Fabricage'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightChangeFabricage1' {
            Path     = 'x:\data\eerste\Fabricage'
            Identity = "$($dcdata.NetbiosName)\Staf"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightReadAFabricage2' {
            Path     = 'x:\data\eerste\Fabricage'
            Identity = "$($dcdata.NetbiosName)\Productie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightFullControlFabricage3' {
            Path     = 'x:\data\eerste\Fabricage'
            Identity = "$($dcdata.NetbiosName)\Fabricage"
            Rights   = @('ChangePermissions')
        }

        file 'algemeen' {
            Type            = 'Directory'
            DestinationPath = 'X:\Data\Tweede\Algemeen'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        FileSystemAccessRule 'AddRightChangeAlgemeen' {
            Path     = 'x:\data\eerste\Algemeen'
            Identity = "$($dcdata.NetbiosName)\Directie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightChangeAlgemeen1' {
            Path     = 'x:\data\eerste\Algemeen'
            Identity = "$($dcdata.NetbiosName)\Administratie"
            Rights   = @('ChangePermissions')
        }
        FileSystemAccessRule 'AddRightReadAlgemeen2' {
            Path     = 'x:\data\eerste\Algemeen'
            Identity = "$($dcdata.NetbiosName)\Domain Users"
            Rights   = @('Read')
        }
        FileSystemAccessRule 'AddRightFullControlAlgemeen3' {
            Path     = 'x:\data\eerste\Algemeen'
            Identity = "$($dcdata.NetbiosName)\Automatisering"
            Rights   = @('FullControl')
        }

        SmbShare 'Data1' {
            Name         = 'Data1'
            Path         = 'x:\data\eerste'
            Description  = 'Eerste datashare'
            ChangeAccess = @('Users')
            DependsOn    = '[File]eerste'
        }
        SmbShare 'Data2' {
            Name                = 'Data2'
            Path                = 'x:\data\tweede'
            Description         = 'Tweede datashare'
            ConcurrentUserLimit = 20
            DependsOn           = '[File]tweede'
        }
        SmbShare 'HomeFolders' {
            Name                = 'UserFolders'
            Path                = 'z:\users\home'
            Description         = 'HomeFolders'
            ConcurrentUserLimit = 30
            DependsOn           = '[File]home'
        }
        SmbShare 'ProfileFolder' {
            Name                = 'UserProfiles'
            Path                = 'z:\users\profiles'
            Description         = 'ProfileFolder'
            ConcurrentUserLimit = 40
            DependsOn           = '[File]home'
        }

        VSS disk_X {
            Drive     = 'X:'
            Size      = 1Gb
            Ensure    = 'Present'
            Dependson = '[Disk]Xvolume'
        }

        VSS disk_Z {
            Drive     = 'Z:'
            Size      = 1Gb
            Ensure    = 'Present'
            Dependson = '[Disk]Xvolume'
        }

        VSSTaskScheduler Disk_X_7 {

            Ensure      = 'present'
            Drive       = 'X:'
            TimeTrigger = '7:00 AM'
            TaskName    = 'Disk_X'
            Credential  = $domaincredential
            DependsOn   = '[VSS]Disk_X'
        }

    }

   #region DHCP
    node $AllNodes.Where( { $_.Role -eq 'DHCP' }).NodeName {       
            

        xDhcpServerAuthorization 'DhcpServerAuthorization' {
            Ensure    = 'Present';
            DependsOn = '[WindowsFeature]DHCP'
        }

        xDhcpServerScope 'DhcpScope' {
            Name          = $DHCPData.DHCPName
            ScopeId       = $DHCPData.DHCPScopeID
            IPStartRange  = $DHCPData.DHCPIPStartRange
            IPEndRange    = $DHCPData.DHCPIPEndRange
            SubnetMask    = $DHCPData.DHCPSubnetMask
            LeaseDuration = $DHCPData.DHCPLeaseDuration
            State         = $DHCPData.DHCPState
            AddressFamily = $DHCPData.DHCPAddressFamily
            DependsOn     = '[WindowsFeature]DHCP'
        }

        xDhcpServerOption 'DhcpOption' {
            ScopeID            = $DHCPData.DHCPScopeID
            DnsServerIPAddress = $DHCPData.DHCPDnsServerIPAddress
            Router             = $DHCPData.DHCPRouter
            AddressFamily      = $DHCPData.DHCPAddressFamily
            DependsOn          = '[xDhcpServerScope]DhcpScope'
        }
        xDhcpServerReservation Client {
            ScopeID          = "$($DHCPData.DHCPScopeID)"
            ClientMACAddress = "$($allnodes.where({$_.nodename -eq "POSHCL1"}).macaddress)".insert(2, "-").insert(5, "-").insert(8, "-").insert(11, "-").insert(14, "-")
            IPAddress        = "$($DHCPData.DHCPReservationIp)"
        }

    } #end DHCP Config
    #endregion
}#end configuration


testdsc -configurationdata $psscriptroot\config.psd1 -outputpath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\vms"