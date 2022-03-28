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
            
        }
    )
}