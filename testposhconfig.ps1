Configuration TestDSC
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration, ComputerManagementDsc, ActiveDirectoryDSC, NetworkingDsc, xDHCPServer, StorageDSC, Mario_cVSS, FileSystemDsc, cNtfsAccessControl, DFSDsc

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

    #region FirstDC
    
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
                HomeDirectory          = "\\poshdc1\UserFolders\$($user.Account)"
                ProfilePath            = "\\poshdc1\UserProfiles\$($user.Account)"
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
        foreach ($feature in $AllNodes.Where( { $_.nodename -eq 'POSHDC2' }).Features) {
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
        WindowsFeature RSAT3
        {
            Ensure = 'Present'
            Name = 'RSAT'
            IncludeAllSubFeature = $true
        }
        Script 'Routing' {
            SetScript  = { powershell.exe c:\ConfigFiles\Routing.ps1 }
            TestScript = { $false }
            GetScript  = { <# Do Nothing #> }
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
    }#End region Client

    #region DomainJoin config
    node $AllNodes.Where( { $_.Role -eq 'domainJoin' }).NodeName 
    {

        

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
    
    node $AllNodes.Where( { $_.Role -eq 'ExtraHdd' }).NodeName 
    {
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
            DependsOn   = '[WaitForDisk]Disk1'
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
        #region Homefolders
        if (($node.nodename) -eq 'POSHDC1') {
            $users = get-content "$((get-item env:userprofile).value)\Documents\github\DSCLabCoen\AD-users.json" | ConvertFrom-Json
            $parentpath = "z:\users\home"

            foreach ($user in $users) {
                $path = "$parentpath\$($user.account)"
                File $user.Account {
                    DestinationPath = $path
                    Type            = 'Directory'
                    Dependson       = '[Disk]ZVolume'
                }
                cNtfsPermissionsInheritance "DisableInheritance$($user.Account)" {
                    Path              = $Path
                    Enabled           = $false
                    PreserveInherited = $false
                    DependsOn         = "[File]$($user.Account)"
                }
                cNtfsPermissionEntry "PermissionSet$($user.Account)" {
                    Ensure                   = 'Present'
                    Path                     = $Path
                    Principal                = "$($dcdata.NetbiosName)\$($user.Account)"
                    AccessControlInformation = @(
                        cNtfsAccessControlInformation {
                            AccessControlType  = 'Allow'
                            FileSystemRights   = 'Modify'
                            Inheritance        = 'ThisFolderSubfoldersAndFiles'
                            NoPropagateInherit = $false
                        }
                    )
                    DependsOn                = "[File]$($user.Account)"
                }
                # Ensure that multiple permission entries are assigned to the local 'Administrators' group.
                cNtfsPermissionEntry "Administrator$($user.Account)" {
                    Ensure                   = 'Present'
                    Path                     = $Path
                    Principal                = 'BUILTIN\Administrators'
                    AccessControlInformation = @(                
                        cNtfsAccessControlInformation {
                            AccessControlType  = 'Allow'
                            FileSystemRights   = 'FullControl'
                            Inheritance        = 'ThisFolderSubfoldersAndFiles'
                            NoPropagateInherit = $false
                        }                
                    )
                    DependsOn                = "[File]$($user.Account)"
                }
                # Ensure that multiple permission entries are assigned to the local 'Administrators' group.
                cNtfsPermissionEntry "Automatisering$($user.Account)" {
                    Ensure                   = 'Present'
                    Path                     = $Path
                    Principal                = "$($dcdata.NetbiosName)\Automatisering"
                    AccessControlInformation = @(                
                        cNtfsAccessControlInformation {
                            AccessControlType  = 'Allow'
                            FileSystemRights   = 'FullControl'
                            Inheritance        = 'ThisFolderSubfoldersAndFiles'
                            NoPropagateInherit = $false
                        }                
                    )
                    DependsOn                = "[File]$($user.Account)"
                }
            }#end foreach users
        }
        #endregion Homefolders
        #region Directie
        file 'Staf' {
            Type            = 'Directory'
            DestinationPath = 'x:\data\eerste\Staf'
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        $Path = 'x:\data\eerste\staf\Directie'
        file 'Directie' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[file]Staf'
        }
        cNtfsPermissionsInheritance DisableInheritanceDirectie {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Directie'
        }
        cNtfsPermissionEntry PermissionSetDirectie1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Directie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Directie'
        }
        cNtfsPermissionEntry PermissionSetDirectie2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Staf"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Directie'
        }
        cNtfsPermissionEntry PermissionSetDirectie3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Administratie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Directie'
        }
        cNtfsPermissionEntry PermissionSetDirectie4 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Directie'
        }
        #endregion Directie
        #region Administratie
        $Path = 'x:\data\eerste\Administratie'
        file 'Administratie' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance 'DisableInheritanceAdministratie' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Administratie'
        }
        cNtfsPermissionEntry PermissionSetAdministratie1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Staf"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Administratie'
        }
        cNtfsPermissionEntry PermissionSetAdministratie2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Administratie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Administratie'
        }
        cNtfsPermissionEntry PermissionSetAdministratie3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Administratie'
        }
        #endregion Administratie
        
        #region Automatisering
        $Path = 'x:\data\eerste\Automatisering'
        file 'Automatisering' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance DisableInheritanceAutomatisering {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Automatisering'
        }
        cNtfsPermissionEntry PermissionSetAutomatisering1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Automatisering'
        }
        #endregion Automatisering
        #region Software
        $Path = 'X:\data\eerste\Software'
        file 'Software' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance 'DisableInheritanceSoftware' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Software'
        }
        cNtfsPermissionEntry PermissionSetSoftware1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "Builtin\Users"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Administratie'
        }
        cNtfsPermissionEntry PermissionSetSoftware2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Administratie'
        }
        #endregion Software
        #region Verkoop
        $Path = 'X:\Data\Tweede\Verkoop'
        file 'Verkoop' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance 'DisableInheritanceVerkoop' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Verkoop'
        }
        cNtfsPermissionEntry PermissionSetVerkoop1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Directie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Verkoop'
        }
        cNtfsPermissionEntry PermissionSetVerkoop2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Staf"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Verkoop'
        }
        cNtfsPermissionEntry PermissionSetVerkoop3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Verkoop"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Verkoop'
        }
        # Ensure that multiple permission entries are assigned to the local 'Administrators' group.
        cNtfsPermissionEntry PermissionSetVerkoop {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Verkoop'
        }
        #endregion Verkoop
        #region Productie
        $Path = 'X:\Data\Tweede\Productie'
        file 'Productie' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance 'DisableInheritanceProductie' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Productie'
        }
        cNtfsPermissionEntry PermissionSetProductie1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Productie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        cNtfsPermissionEntry PermissionSetProductie2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Fabricage"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        cNtfsPermissionEntry PermissionSetProductie3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Directie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        cNtfsPermissionEntry PermissionSetProductie4 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Staf"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        # Ensure that multiple permission entries are assigned to the local 'Administrators' group.
        cNtfsPermissionEntry PermissionSetProductie {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        #endregion Productie
        #region Fabricage
        $Path = 'X:\Data\Tweede\Productie\Fabricage'
        file 'Fabricage' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[file]productie'
        }
        cNtfsPermissionsInheritance 'DisableInheritancePFabricage' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Fabricage'
        }
        cNtfsPermissionEntry PermissionSetFabricage1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Productie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Fabricage'
        }
        cNtfsPermissionEntry PermissionSetFabricage2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Fabricage"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Fabricage'
        }
        cNtfsPermissionEntry PermissionSetFabricage3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Directie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Fabricage'
        }
        cNtfsPermissionEntry PermissionSetFabricage4 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Staf"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Productie'
        }
        # Ensure that multiple permission entries are assigned to the local 'Administrators' group.
        cNtfsPermissionEntry PermissionSetFabricage {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Fabricage'
        }
        #endregion Fabricage
        #region Algemeen
        $Path = 'X:\Data\Tweede\Algemeen'
        file 'algemeen' {
            Type            = 'Directory'
            DestinationPath = $Path
            Ensure          = "Present"
            DependsOn       = '[Disk]XVolume'
        }
        cNtfsPermissionsInheritance 'DisableInheritanceAlgemeen' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $false
            DependsOn         = '[File]Algemeen'
        }
        cNtfsPermissionEntry PermissionSetAlgemeen1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "BUILTIN\Users"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Algemeen'
        }
        cNtfsPermissionEntry PermissionSetAlgemeen2 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Directie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Algemeen'
        }
        cNtfsPermissionEntry PermissionSetAlgemeen3 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Administratie"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ReadAndExecute'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Algemeen'
        }
        cNtfsPermissionEntry PermissionSetAlgemeen4 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "$($dcdata.NetbiosName)\Automatisering"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'FullControl'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn                = '[File]Algemeen'
        }
        #endregion Algemeen

        SmbShare 'Data1' {
            Name         = 'Data1'
            Path         = 'x:\data\eerste'
            Description  = 'Eerste datashare'
            ChangeAccess = @('Users')
            FullAccess = @("$($dcdata.NetbiosName)\Automatisering")
            DependsOn    = '[File]eerste'
        }
        SmbShare 'Data2' {
            Name                = 'Data2'
            Path                = 'x:\data\tweede'
            Description         = 'Tweede datashare'
            ConcurrentUserLimit = 20
            DependsOn           = '[File]tweede'
            ChangeAccess = @('Users')
            ReadAccess = @()
            FullAccess = @("$($dcdata.NetbiosName)\Automatisering")
        }
        SmbShare 'HomeFolders' {
            Name                = 'UserFolders'
            Path                = 'z:\users\home'
            Description         = 'HomeFolders'
            ConcurrentUserLimit = 30
            FolderEnumerationMode = 'AccessBased'
            FullAccess = @('Everyone')
            DependsOn           = '[File]home'
        }
        SmbShare 'ProfileFolder' {
            Name                = 'UserProfiles'
            Path                = 'z:\users\profiles'
            Description         = 'ProfileFolder'
            ConcurrentUserLimit = 40
            FolderEnumerationMode = 'AccessBased'
            FullAccess = @('Everyone')
            DependsOn           = '[File]home'
        }
        #region profile permissions
        $Path = 'z:\users\profiles'
        cNtfsPermissionsInheritance 'DisableInheritanceProfile' {
            Path              = $Path
            Enabled           = $false
            PreserveInherited = $true
            DependsOn         = '[File]Home'
        }
        cNtfsPermissionEntry PermissionSetProfile1 {
            Ensure                   = 'Present'
            Path                     = $Path
            Principal                = "BUILTIN\Users"
            AccessControlInformation = @(
                cNtfsAccessControlInformation {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'ListDirectory', 'ReadData', 'AppendData', 'CreateFiles'
                    Inheritance        = 'ThisFolderOnly'
                    NoPropagateInherit = $false
                }
            )
        }
        #endregion profilepermissions
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
    
    node $AllNodes.Where{ $_.Role -eq 'MS' }.NodeName
    {

    }
    #region DFS
    node $AllNodes.Where( { $_.Role -eq 'DFS' }).NodeName 
    {
        File DFS
        {
            destinationPath = 'X:\data\eerste\public'
            Type = 'Directory'            
        }
        SmbShare DFSSHare
        {
            Name = 'Public'
            Path = 'X:\data\eerste\public'
            FullAccess = 'Everyone'
            DependsOn = '[File]Dfs'
        }
        # Configure the namespace
        DFSNamespaceRoot DFSNamespaceRoot_Domain_Software_POSHDC1
        {
            Path                 = "\\$($DCData.DomainName)\Public"
            TargetPath           = '\\poshdc1\Public'
            Ensure               = 'Present'
            Type                 = 'DomainV2'
            Description          = 'AD Domain based DFS namespace for storing software installers'
            PsDscRunAsCredential = $DomainCredential
        } # End of DFSNamespaceRoot Resource

        
       
        # Configure the Replication Group
        DFSReplicationGroup RGPublic
        {
            GroupName = 'Public'
            Description = 'Public files for use by all departments'
            Ensure = 'Present'
            Members = 'POSHDC1','POSHDC2'
            Folders = 'Software'
            Topology = 'Fullmesh'
            PSDSCRunAsCredential = $DomainCredential
            
        } # End of RGPublic Resource

        DFSReplicationGroupFolder RGSoftwareFolder
        {
            GroupName = 'Public'
            FolderName = 'Software'
            Description = 'DFS Share for storing software installers'
            DirectoryNameToExclude = 'Temp'
            PSDSCRunAsCredential = $DomainCredential
            DependsOn = '[DFSReplicationGroup]RGPublic'
        } # End of RGPublic Resource

        DFSReplicationGroupMembership RGPublicSoftwareFS1
        {
            GroupName = 'Public'
            FolderName = 'Software'
            ComputerName = 'POSHDC1'
            ContentPath = 'x:\Data\Eerste\Software'
            PrimaryMember = $true
            PSDSCRunAsCredential = $DomainCredential
            DependsOn = '[DFSReplicationGroupFolder]RGSoftwareFolder'
        } # End of RGPublicSoftwareFS1 Resource

        DFSReplicationGroupMembership RGPublicSoftwareFS2
        {
            GroupName = 'Public'
            FolderName = 'Software'
            ComputerName = 'FileServer2'
            ContentPath = 'x:\Data\Eerste\Software'
            PSDSCRunAsCredential = $DomainCredential
            DependsOn = '[DFSReplicationGroupFolder]RGSoftwareFolder'
        } # End of RGPublicSoftwareFS2 Resource
    }#endregion DFS
}#end configuration


testdsc -configurationdata $psscriptroot\config.psd1 -outputpath "$((get-item env:userprofile).value)\Documents\GitHub\DSCLabCoen\dsc\vms"