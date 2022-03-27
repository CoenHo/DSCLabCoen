function New-UnattendXml
{

    <#
            .Synopsis
            Create a new basic Unattend.xml
            .DESCRIPTION
            Creates a new Unattend.xml and sets the admin password, Skips any prompts, logs in a set number of times (default 0) and starts a powershell script (default c:\pstemp\firstrun.ps1).
            If no Path is provided a the file will be created in a temp folder and the path returned.
            .EXAMPLE
            New-UnattendXml -logonCount 1
            .EXAMPLE
            New-UnattendXml -Path c:\temp\Unattent.xml -logonCount 100
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    Param
    (
        # set new machine to this computername
        [Parameter(Mandatory = $true, 
                ValueFromPipeline = $true,
                ValueFromPipelineByPropertyName = $true, 
        Position = 0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName,

        # Output Path
        [Alias('FilePath', 'FullName', 'pspath')]
        [ValidateScript({
                    (-not (Test-Path -Path $_))
        })]
        [string]
        $Path = "$(New-TemporaryDirectory)\unattend.xml",

        # Number of times that the local Administrator account should automaticaly login (default 1)
        [int]
        $LogonCount = 1,

        # set new machine to this timezone (default W. Europe Standard Time)
        [string]
        $TimeZone = 'W. Europe Standard Time'

        
    )

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
    if ($pscmdlet.ShouldProcess('$path', 'Create new Unattended.xml'))
    {
        try
        {
            $unattend = $unattendTemplate.Clone()
            (Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).TimeZone = $Timezone
            (Get-UnattendChunk -pass 'specialize' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).TimeZone = $Timezone
            (Get-UnattendChunk -pass 'specialize' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).ComputerName = [string]$ComputerName
            #((Get-UnattendChunk -pass 'oobeSystem' -component 'Microsoft-Windows-Shell-Setup' -arch 'amd64' -unattend $unattend).FirstLogonCommands.SynchronousCommand | where Description -eq 'PowerShellFirstRun' ).CommandLine = "$PowerShellStartupCmd $ScriptPath"
            $unattend.Save($Path)
            Get-ChildItem $Path
        }
        catch 
        {
            throw $_.Exception.Message
        }
    }
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

function New-TemporaryDirectory
{
    <#
      .Synopsis
      Create a new Temporary Directory
      .DESCRIPTION
      Creates a new Directory in the $env:temp and returns the System.IO.DirectoryInfo (dir)
      .EXAMPLE
      $TempDirPath = NewTemporaryDirectory
      #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.DirectoryInfo])]
    Param
    (
    )

    #return [System.IO.Directory]::CreateDirectory((Join-Path $env:Temp -Ch ([System.IO.Path]::GetRandomFileName().split('.')[0])))

    Begin
    {
        try
        {
            if ($PSCmdlet.ShouldProcess($env:temp))
            {
                $tempDirPath = [System.IO.Directory]::CreateDirectory((Join-Path -Path $env:temp -ChildPath ([System.IO.Path]::GetRandomFileName().split('.')[0])))
            }
        }
        catch
        {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($_.Exception, 'NewTemporaryDirectoryWriteError', 'WriteError', $env:temp)
            Write-Error -ErrorRecord $errorRecord
            return
        }

        if ($tempDirPath)
        {
            Get-Item -Path $tempDirPath.FullName
        }
    }
}