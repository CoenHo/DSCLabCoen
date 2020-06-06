@{
    AllNodes   = 
    @(
        @{
            #Common data for all nodes
            NodeName                    = '*'
            PSDscAllowPlainTextPassword = $True
            PSDscAllowDomainUser        = $true            

            # Common networking
            InterfaceAlias              = 'LAB'
            DefaultGateway              = '192.168.5.254'
            SubnetMask                  = 24
            AddressFamily               = 'IPv4'
            IPNetwork                   = '192.168.5.0/24'
            DnsServerAddress            = @('192.168.5.1', '192.168.5.2')
            FirewallRules               = @('FPS-ICMP4-ERQ-In')
        },
        @{
            # Node Specific Data
            NodeName   = 'POSHDC1'
            Role       = @('FirstDC', 'DHCP', 'ExtraHdd')
            IpAddress  = '192.168.5.1'
            MacAddress = '001523be0c01'
            Features   = @('AD-Domain-Services', 'DHCP', 'FS-Resource-Manager', 'FS-DFS-Replication', 'FS-DFS-NameSpace')
        },
        @{
            NodeName   = 'POSHDC2'
            Role       = @('SecondDC', 'ExtraHdd')
            IpAddress  = '192.168.5.2'
            MacAddress = '001523be0c02'
            Features   = @('AD-Domain-Services', 'FS-Resource-Manager', 'FS-DFS-Replication', 'FS-DFS-NameSpace')
        },        
        @{
            NodeName   = 'POSHMS1'
            Role       = @('MS', 'domainJoin')
            MacAddress = '001523be0d01'
        },
        @{
            NodeName   = 'POSHMS2'
            Role       = @('MS', 'domainJoin')
            MacAddress = '001523be0d02'
        },
        @{
            NodeName   = 'POSHMS3'
            Role       = @('MS', 'domainJoin')
            MacAddress = '001523be0d03'
        },
        @{
            NodeName   = 'POSHMS4'
            Role       = @('MS', 'domainJoin')
            MacAddress = '001523be0d04'
        },
        @{
            NodeName   = 'POSHCL1'
            Role       = @('CLIENT', 'domainJoin')
            MacAddress = '001523be0c05'
        }
        ,
        @{
            NodeName   = 'POSHCL2'
            Role       = @('CLIENT')
            MacAddress = '001523be0c06'
        }
    )
    Credential = @{
        LabPassword = 'P@ssw0rd'
    }
    DCData     = @{
        DomainName     = "AC8-CoeHod.int"
        DomainDN       = "DC=AC8-CoeHod,DC=int"
        DCDatabasePath = "C:\NTDS"
        DCLogPath      = "C:\NTDS"
        SysvolPath     = "C:\Sysvol"
        OU             = "CHAfdelingen"
        NetBiosName    = "AC8-CoeHod"
    }
 
    DHCPData   = @{
        DHCPFeatures           = @('DHCP')
        DHCPName               = 'LAN'
        DHCPIPStartRange       = '192.168.5.100'
        DHCPIPEndRange         = '192.168.5.250'
        DHCPSubnetMask         = '255.255.255.0'
        DHCPState              = 'Active'
        DHCPAddressFamily      = 'IPv4'
        DHCPLeaseDuration      = '00:08:00'
        DHCPScopeID            = '192.168.5.0'
        DHCPDnsServerIPAddress = @('192.168.5.1', '192.168.5.2')
        DHCPRouter             = '192.168.5.254'
        DHCPReservationIp      = '192.168.5.150'
    }
}
# Save ConfigurationData in a file with .psd1 file extension