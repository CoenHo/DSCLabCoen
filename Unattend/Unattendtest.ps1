function New-UnattendXml
{

    <#
            .Synopsis
            Create a new basic Unattend.xml
            .DESCRIPTION
            Creates a new Unattend.xml and sets the admin password, Skips any prompts, logs in a set number of times (default 0) and starts a powershell script (default c:\pstemp\firstrun.ps1).
            If no Path is provided a the file will be created in a temp folder and the path returned.
            .EXAMPLE
            New-UnattendXml -AdminPassword 'P@ssword' -logonCount 1
            .EXAMPLE
            New-UnattendXml -Path c:\temp\Unattent.xml -AdminPassword 'P@ssword' -logonCount 100 -ScriptPath c:\pstemp\firstrun.ps1
            .INPUTS
            Inputs to this cmdlet (if any)
            .OUTPUTS
            Output from this cmdlet (if any)
            .NOTES
            General notes
            .COMPONENT
            The component this cmdlet belongs to
            .ROLE
            The role this cmdlet belongs to
            .FUNCTIONALITY
            The functionality that best describes this cmdlet
    #>
    
    Begin
    {
        $unattendTemplate = [xml]@"
<?xml version="1.0" encoding="utf-8"?>
                <unattend xmlns="urn:schemas-microsoft-com:unattend">
                    <settings pass="oobeSystem">
                        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                            <InputLocale>0409:00000409</InputLocale>
                            <SystemLocale>en-US</SystemLocale>
                            <UILanguage>en-US</UILanguage>
                            <UILanguageFallback>en-US</UILanguageFallback>
                            <UserLocale>en-US</UserLocale>
                        </component>
                        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                            <OOBE>
                                <VMModeOptimizations>
                                    <SkipAdministratorProfileRemoval>false</SkipAdministratorProfileRemoval>
                                </VMModeOptimizations>
                                <HideEULAPage>true</HideEULAPage>
                                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                                <ProtectYourPC>1</ProtectYourPC>
                                <UnattendEnableRetailDemo>false</UnattendEnableRetailDemo>
                            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>UABhAHMAcwB3AG8AcgBkAA==</Value>
                            <PlainText>false</PlainText>
                        </Password>
                        <Description>Local admin</Description>
                        <DisplayName>Admin</DisplayName>
                        <Group>Administrators</Group>
                        <Name>Admin</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <RegisteredOrganization>Eleven Forum</RegisteredOrganization>
            <RegisteredOwner>Kari</RegisteredOwner>
            <TimeZone>W. Europe Standard Time</TimeZone>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>CL1</ComputerName>
            <OEMName>Hodzelmans Lab</OEMName>
            <RegisteredOrganization>Hodzelmans Lab</RegisteredOrganization>
            <RegisteredOwner>Admin</RegisteredOwner>
            <TimeZone>W. Europe Standard time</TimeZone>
        </component>
    </settings>
    <cpi:offlineImage cpi:source="wim:h:/unattend/install.wim#Windows 10 Pro" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
"@
}
Process
{
    
        
            $unattend = $unattendTemplate.Clone()
           (Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).TimeZone = [string]'Klote'
            (Get-UnattendChunk -pass 'specialize' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).TimeZone = 'Klote'
            (Get-UnattendChunk -pass 'specialize' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).ComputerName = 'TEST1'
            #(Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).UserAccounts.AdministratorPassword.Value = $AdminPassword
            #(Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).AutoLogon.Password.Value = $AdminPassword
            #(Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).AutoLogon.LogonCount = [string]$logonCount
            
           
            $unattend.Save('C:\temp\test.xml')
            
        
    }
}


function Get-UnattendChunk 
{
param
(
    [string] $pass, 
    [string] $component,
    [string] $arch, 
    [xml] $unattend
) 

# Helper function that returns one component chunk from the Unattend XML data structure
return $unattend.unattend.settings |
Where-Object -Property pass -EQ -Value $pass |
Select-Object -ExpandProperty component |
Where-Object -Property name -EQ -Value $component |
Where-Object -Property processorArchitecture -EQ -Value $arch
}