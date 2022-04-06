Configuration TestDSC
{
    $modules = @("ComputerManagementDsc", "ActiveDirectoryDSC", "NetworkingDsc", "xDHCPServer", "StorageDSC", "Mario_cVSS", "FileSystemDsc", "cNtfsAccessControl", "DFSDsc", "cChoco", "xRemoteDesktopAdmin")
    foreach ($module in $modules) {
        if (-not(test-path "C:\Users\chodz\Documents\PowerShell\Modules\$module")) {
            install-module $module -force
        }
        
    }
    #Import-Module -Name "PSDesiredStateConfiguration","ComputerManagementDsc", "ActiveDirectoryDSC", "NetworkingDsc", "xDHCPServer", "StorageDSC", "Mario_cVSS", "FileSystemDsc", "cNtfsAccessControl", "DFSDsc", "cChoco", "xRemoteDesktopAdmin"
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
        if(-not($node.nodename -like 'CLT*'))
        {
            xRemoteDesktopAdmin RemoteDesktopSettings
            {
                Ensure = 'Present'
                UserAuthentication = 'Secure'
            }
            #region Firewall Rules        
            $FireWallRules = $ConfigurationData.FirewallRules.FirewallRuleNames

            foreach ($Rule in $FireWallRules)
            {
                Firewall $Rule
                {
                    Name    = $Rule
                    Enabled = 'True'
                    Profile = ('Domain', 'Private')
                }
            } #End foreach
            #endregion
        }#end if not client
        if ($node.Nodename -eq 'RTR-COEHODE2X') {
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
            if (($node.Nodename) -ne 'RTR-COEHODE2X') {
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

        
        

    }#end allnodes

    #region FirstDC
    
    node $AllNodes.Where{ $_.Role -eq 'FirstDC' }.NodeName
    {
        Computer $Node.NodeName {
                
            Name = $Node.NodeName
            
        }
        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'DC1-COEHODE2X' }).Features) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;

            }
        } #End foreach
        WindowsFeature RSAT1
        {
            Ensure = 'Present'
            Name = 'RSAT'
            IncludeAllSubFeature = $true
        }
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
                HomeDrive              = 'H:'
                HomeDirectory          = "\\DC1-COEHODE2X\UserFolders\$($user.Account)"
                ProfilePath            = "\\DC1-COEHODE2X\UserProfiles\$($user.Account)"
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
                ManagedBy  = $group.Manager
            }
        }# end region groups
        ADGroup DomainAdmin {
            GroupName        = 'Domain Admins'
            MembersToInclude = 'Automatisering'
            DependsOn        = '[ADGroup]Automatisering'
        }
        ADGroup EnterpriseAdmin {
            GroupName        = 'Enterprise Admins'
            MembersToInclude = 'Automatisering'
            DependsOn        = '[ADGroup]Automatisering'
        }
        ADGroup Admin {
            GroupName        = 'Administrators'
            MembersToInclude = 'Automatisering'
            DependsOn        = '[ADGroup]Automatisering'
        }
        
    }
    #endregion firstdc
    
    
    #region SecondDC
    node $AllNodes.Where{ $_.Role -eq 'SecondDC' }.NodeName
    {
        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'DC2-COEHODE2X' }).Features) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
            }
        } #End foreach
        WindowsFeature RSAT2
        {
            Ensure = 'Present'
            Name = 'RSAT'
            IncludeAllSubFeature = $true
        }
        WaitForADDomain 'DscForestWait' {
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

    
}#end configuration


testdsc -configurationdata $psscriptroot\config.psd1 -outputpath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\vms"