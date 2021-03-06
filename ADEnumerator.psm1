#Requires -Version 2
<#
Install steps:

1) Since this is a module, you may need to disable the execution
   policy. From an elevated prompt, execute the following:

   Set-ExecutionPolicy Unrestricted

2) From a regular PowerShell prompt, you can now import the module.

   Import-Module ADEnumerator.psm1

   ADEnumerator.psm1 contains a lot of functions which will each accept
   an existing LDAP session parameteter (LDAPSession) or a new one (DCHostName).
   Call the New-LDAPSession function and set it to a variable to create an existing
   LDAP session that will be passed to the other functions. 

Notes:

This is only ever intended to be executed on your attacker system.
It will run on any system though, but you will always have to provide creds.

You will need a valid domain controller for this to work. 
How do you get a list of domain controllers without a domain system? 
Two ways:
ipconfig -> will get you a DNS suffix
nltest /dclist:{domain} #will give you an error, but will also list one DC

nslookup
set type=any
{domain} #will list name servers...generally those are DCs


Use Cases:

1. You harvest a domain credential from a printer, responder, etc. But don't have access
to a domain system. You can use the credential to perform additional enumeration on the domain.

2. Find out what you can do with the credential you harvested. What group membership, maybe a system with similiar 
naming convetion of the username which indicates the user may have local admin on the system.

3. You are provided credentials to start an internal assessment, but not a domain system.

4. You just want to do domain enumeration quickly

Function Overview:

New-LDAPSession - Creates an LDAP Session
Invoke-SearchAD - Searches Active Directory for string
Get-AllADUsers - Will get all user accounts from Active Directory
Get-GroupMembership - Will get user accounts who are members of specified group
Get-AllGroups - Gets a list of all groups
Get-DomainControllers - Gets a list of domain controllers
Get-Computers - Gets a list of computers or computer versions
Get-UserMembership - Will get details about specified user

.SYNOPSIS

Active Directory enumeration from non-domain system.

Author: Evan Peña
Credit: Matt Graeber for code review and code improvements
Required Dependencies: Domain Credential
Optional Dependencies: Expand-Data
 
.DESCRIPTION

ADEnumerator.psm1 allows red teamers to query LDAP with a standard user account
from a system not joined to a domain. It's common that during a red team assessment
you will harvest credentials from printers, files, etc. But sometimes you don't know
what these credentials do.

Instead of throwing the one set of credentials you got at all systems to see where you
are local admin, you can tailor your attack to specific systems. ADEnumerator.ps1 allows
you to find out information about the account you compromised. It will also perform all 
the Active Directory enumeration you can do from a domain system using the creds you obtained.

.EXAMPLE

C:\PS> import-module ADEnumerator.psm1

C:\PS> $Domain = New-LDAPSession -DCHostName ServerDC.contoso.local

Description
-----------
Will establish an LDAP session with domain controller ServerDC.contoso.local 
and save it into variable $domain

.EXAMPLE

C:\PS> Get-AllADUsers -LDAPSession $domain

Description
-----------
Will return all users in the domain using 
the existing LDAP session from New-LDAPSession

#>
function New-LDAPSession
{
<#
.SYNOPSIS

Creates an LDAP Session

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Will establish an LDAP session with a valid domain account.
It will return an object that can be used for other functions
in this module.

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.EXAMPLE

$Domain = New-LDAPSession -DCHostName ServerDC.contoso.local
#>
  [CmdletBinding(DefaultParameterSetName='DomainInfoSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential		 
		)
		
	$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)

	#Ensure creds are good and can establish connection
	trap { $script:err = $_ ; continue } &{ $domain.Bind($true); $script:err = $null }
	if ($err.Exception.ErrorCode -ne -2147352570) 
	{
	  Write-Host -Fore Red $err.Exception.Message
	  break
	}
	else
	{
	  Write-Host -Fore Green "Connection established."
	}
	#Write-Host Logon failure: unknown user name or bad password.

	return $domain
}

function Invoke-SearchAD
{
<#
.SYNOPSIS

Searches Active Directory for string

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Will search Active Directory for a string like something. 
If you know a persons first name, but not sure of their last name,
you can use this search to find all users with a first name specified

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.PARAMETER SearchString

Specifies the search string you are looking for

.PARAMETER Groups

Switch that will specify to search all groups in active directory for specified string

.PARAMETER Users

Switch that will specify to search all users and machines in active directory for specified string

.EXAMPLE

Invoke-SearchAD -DCHostName ServerDC.contoso.local -SearchString *evan* -Users

.EXAMPLE

Invoke-SearchAD -LDAPSession $domain -SearchString *admin* -Groups

.EXAMPLE

Invoke-SearchAD -LDAPSession $domain -SearchString *pena* -Users
#>
  [CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoUsers")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoUsers")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionUsers")]
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoUsers")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionUsers")]
		 [ValidateNotNullOrEmpty()]
		 [String]
         $SearchString,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoGroups")]
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionGroups")]
		 [ValidateNotNullOrEmpty()]
		 [switch]
         $Groups,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoUsers")]
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionUsers")]
		 [ValidateNotNullOrEmpty()]
		 [switch]
         $Users		 
		)
		
	if ($PSboundparameters["DCHostName"]) {
		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
	}
	else {
		$domain = $LDAPSession
	}
	
	if ($PSboundparameters["Groups"]) {
		$type = "ObjectCategory=group"
	}
	else {
		$type = "objectClass=user"
	}

	$dsLookFor = new-object DirectoryServices.DirectorySearcher($domain)
	$dsLookFor.filter = "(&($type)(sAMAccountName=$SearchString))"
	$dsLookFor.CacheResults = $true
	$dsLookFor.SearchScope = "Subtree"
	$dsLookFor.PageSize = 1000
	$lstUsr = $dsLookFor.findall()
	
	foreach ($usrTmp in $lstUsr) 
	{		
		$usrTmp.Properties["samaccountname"][0]
	}
}

#This function will get all active AD user accounts to include the samaccountname and full name
function Get-AllADUsers
{
<#
.SYNOPSIS

Will get all user accounts from Active Directory

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Will get all user accounts from Active Directory

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.EXAMPLE

Get-AllADUsers -DCHostName ServerDC.contoso.local

.EXAMPLE

Get-AllADUsers -LDAPSession $domain
#>
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]		 
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession
		 
		)
		
	if ($PSboundparameters["DCHostName"]) {
		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
	}
	else {
		$domain = $LDAPSession
	}
		
	$dsLookFor = New-Object System.DirectoryServices.DirectorySearcher
    #$dsLookFor.filter ="(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
    $dsLookFor.filter ="(sAMAccountType=805306368)" #per Carlos' Derby talk slide 404
	$dsLookFor.SearchRoot = $domain
	$dsLookFor.PropertiesToLoad.Add("samaccountname")
	$dsLookFor.PageSize = 1000
	$dsLookFor.Filter = $strFilter
	$dsLookFor.SearchScope = "Subtree"

	$colProplist = "name"
	foreach ($i in $colPropList){$dsLookFor.PropertiesToLoad.Add($i)}

	$colResults = $dsLookFor.FindAll()

	foreach ($objResult in $colResults) {
        if ($objResult.Properties['samaccountname'])
		{
			if (!($objResult.Properties['samaccountname'][0].EndsWith("$")))
			{
				New-Object PSObject -Property @{
					Name = $objResult.Properties['name'][0]
					Account = $objResult.Properties['samaccountname'][0]
				}	
			}
		}
    }
}

#######get distinguishedname for groups to add to the group of interest
Function Invoke-SearchGroups
{
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession,
         
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]
		 [ValidateNotNullOrEmpty()]
		 [String]
         $GroupName
		 
		)
	$dsLookFor = new-object System.DirectoryServices.DirectorySearcher($LDAPSession)
	$dsLookFor.filter = $Filter = "(&(ObjectCategory=group))"
	$dsLookFor.PageSize = 1000;
	$dsLookFor.SearchScope = "Subtree"
	$lstUsr = $dsLookFor.Findall()
	foreach ($usrTmp in $lstUsr) 
	{
		#$usrTmp.Properties['distinguishedname']
		$grpName = $usrTmp.Properties['name']
		if ($GroupName -eq $grpName)
		{
			$dg = $usrTmp.Properties['distinguishedname']
		}
	}
	return $dg
}

Function Get-GroupMembership
{
<#
.SYNOPSIS

Will get user accounts who are members of specified group

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Will get user accounts who are members of specified group

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.PARAMETER GroupName

Specifies group name you want members of. Accepts single group name, array of group names, or a list piped to it

.EXAMPLE

Get-GroupMembership -DCHostName ServerDC.contoso.local -GroupName finance

.EXAMPLE

gc groupNameList.txt | Get-GroupMembership -DCHostName ServerDC.contoso.local

.EXAMPLE

Get-GroupMembership -LDAPSession $domain -GroupName "domain admins" 
#>
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]		 
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]		 
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet", ValueFromPipeLine=$True)]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet", ValueFromPipeLine=$True)]
		 [ValidateNotNullOrEmpty()]
		 [String[]]
         $GroupName
		 
		)
	
    Process {	
    	if ($PSboundparameters["DCHostName"]) {
    		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
        }
    	else {
    		$domain = $LDAPSession
    	}
    	
        foreach ($group in $GroupName) {	
        	$dsLookFor = new-object System.DirectoryServices.DirectorySearcher($domain)
        	$DNGrp = Invoke-SearchGroups -GroupName $group -LDAPSession $domain
        	$dsLookFor.filter = "(&(objectCategory=user)(memberOf=$DNGrp))"
			$dsLookFor.PageSize = 1000;
        	$dsLookFor.SearchScope = "subtree"; 
        	$n = $dsLookFor.PropertiesToLoad.Add("cn"); 
        	$n = $dsLookFor.PropertiesToLoad.Add("distinguishedName");
        	$n = $dsLookFor.PropertiesToLoad.Add("samaccountname");

        	$lstUsr = $dsLookFor.findall()
            "All Users for: $group"
        	foreach ($usrTmp in $lstUsr) 
        	{
        		if ($usrTmp.Properties['samaccountname'] -and ($usrTmp.Properties['samaccountname'][0].Length -ne 0))
        		{
        			$usrTmp.Properties["samaccountname"][0]
        		}
        	}
            "`n"
        }
    }
}

function Get-AllGroups
{
<#
.SYNOPSIS

Gets a list of all groups

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Gets a list of all groups

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.EXAMPLE

Get-AllGroups -DCHostName ServerDC.contoso.local

.EXAMPLE

Get-AllGroups -LDAPSession $domain
#>
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]		 
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession
		 
		)
		
	if ($PSboundparameters["DCHostName"]) {
		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
	}
	else {
		$domain = $LDAPSession
	}
    $dsLookFor = new-object System.DirectoryServices.DirectorySearcher($domain)
    $dsLookFor.filter = $Filter = "(&(ObjectCategory=group))"
	$dsLookFor.PageSize = 1000;
    $dsLookFor.SearchScope = "Subtree"
    $n = $dsLookFor.PropertiesToLoad.Add("cn"); 
    $n = $dsLookFor.PropertiesToLoad.Add("description");
    $n = $dsLookFor.PropertiesToLoad.Add("samaccountname");
    $lstUsr = $dsLookFor.Findall()

    foreach ($usrTmp in $lstUsr) 
	{
		if ($usrTmp.Properties['samaccountname'] -and ($usrTmp.Properties['samaccountname'][0].Length -ne 0))
		{
			$SamAccountName = $usrTmp.Properties['samaccountname'][0]

			$Description = $null

			if ($usrTmp.Properties['description'] -and ($usrTmp.Properties['description'][0].Length -ne 0)) {
				$Description = $usrTmp.Properties['description'][0]
			}

		 New-Object PSObject -Property @{
		  SAMAccountName = $SamAccountName
		  Description = $Description    
		 }
		}
	}
}

Function Get-DomainControllers
{
<#
.SYNOPSIS

Gets a list of domain controllers

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Gets a list of domain controllers

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.EXAMPLE

Get-DomainControllers -DCHostName ServerDC.contoso.local

.EXAMPLE

Get-DomainControllers -LDAPSession $domain
#>
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]		 
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession
		 
		)
		
	if ($PSboundparameters["DCHostName"]) {
		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
	}
	else {
		$domain = $LDAPSession
	}
    $dsLookFor = new-object System.DirectoryServices.DirectorySearcher($domain)			
	$dsLookFor.filter = "(&(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192))" #Taken from Carlos' Derby talk slide 404
	$dsLookFor.PageSize = 1000;
	$dsLookFor.SearchScope = "subtree"; 
	$n = $dsLookFor.PropertiesToLoad.Add("sAMAccountName");

	$lstUsr = $dsLookFor.findall()
	foreach ($usrTmp in $lstUsr) 
	{		
		$usrTmp.Properties["samaccountname"][0].replace("$","")
	}
}

#LDAP filtered referenced fro here: http://blogs.msdn.com/b/muaddib/archive/2011/10/24/active-directory-ldap-searches.aspx
Function Get-Computers
{
<#
.SYNOPSIS

Gets a list of computers or computer versions

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

This function will get a list of computers from Active Directory. This function
can be flexible. If you want only SQL servers, Windows Servers, specific versions, etc.
The function will default to all computers if a parameter is not specified

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.PARAMETER Sql

Will return a list of SQL systems from Active Directory

.PARAMETER Servers

Will return a list of all Windows servers from Active Directory

.PARAMETER Windows

Will return a list of all Windows systems from Active Directory.
Includes Workstations and Servers

.PARAMETER Version

Specifies the operating system version you want.
Following values accepted: 7, 2008, XP, 2000, 2003, Vista, 2012, 8, 10

.EXAMPLE

Get-Computers -DCHostName ServerDC.contoso.local -Sql

.EXAMPLE

Get-Computers -LDAPSession $domain -Servers | Out-File allServers.txt

.EXAMPLE

Get-Computers -LDAPSession $domain -Version 2000 | Out-File all2000Systems.txt

.EXAMPLE

Get-Computers -LDAPSession $domain -Windows
#>
	[CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
    Param
       (
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetSql")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetServers")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetWindows")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetVersion")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetSql")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetServers")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetWindows")]
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetVersion")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetSql")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetServers")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetWindows")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetVersion")]
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetSql")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetSql")]
		 [Switch]
         $Sql,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetServers")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetServers")]
         [Switch]
         $Servers,
         
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetWindows")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetWindows")]
         [Switch]
         $Windows,
         
         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSetVersion")]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSetVersion")]
         [ValidateSet('7', '2008', 'XP', '2000', '2003', 'Vista', '2012', '8', '10')]
         [String]
         $Version
       )
	   
	   if ($PSboundparameters["DCHostName"]) {
		$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
	   }
		else {
			$domain = $LDAPSession
		}
    
    $AllFilter = '(objectCategory=computer)'
    $SqlFilter = '(&(objectCategory=computer)(servicePrincipalName=MSSQLSvc*)(operatingSystem=Windows Server*))'
    $ServerFilter = '(&((objectCategory=computer))(operatingSystem=Windows Server*))'
    $WindowsFilter = '(&(objectCategory=computer)(operatingSystem=Windows*))'
    $ServerVersions = @('2008', '2012', '2003')

    switch ($PSCmdlet.ParameterSetName) {
        'LDAPSessionSet' { $Filter = '(objectCategory=computer)' }
        'DomainInfoSet' { $Filter = '(objectCategory=computer)' }

        'LDAPSessionSetSql' { $Filter = $SqlFilter }
        'DomainInfoSetSql' { $Filter = $SqlFilter }

        'LDAPSessionSetServers' { $Filter = $ServerFilter }
        'DomainInfoSetServers' { $Filter = $ServerFilter }

        'LDAPSessionSetWindows' { $Filter = $WindowsFilter }
        'DomainInfoSetWindows' { $Filter = $WindowsFilter }

        'DomainInfoSetVersion' {
            if ($ServerVersions -contains $Version) {
                $Filter = "(&(objectCategory=computer)(operatingSystem=Windows Server $version*))"
            } else {
                $Filter = "(&(objectCategory=computer)(operatingSystem=Windows $version*))"
            }
        }

        'LDAPSessionSetVersion' {
            if ($ServerVersions -contains $Version) {
                $Filter = "(&(objectCategory=computer)(operatingSystem=Windows Server $version*))"
            } else {
                $Filter = "(&(objectCategory=computer)(operatingSystem=Windows $version*))"
            }
        }
    }
	$dsLookFor = new-object System.DirectoryServices.DirectorySearcher($domain)
    $dsLookFor.filter = $Filter
	$dsLookFor.PageSize = 1000;
    $dsLookFor.SearchScope = "subtree"
    $n = $dsLookFor.PropertiesToLoad.Add("samaccountname")

    $lstUsr = $dsLookFor.findall()

    # Are you sure you'll still only interested in just the samaccountname and description?
    foreach ($usrTmp in $lstUsr) 
    {
        if ($usrTmp.Properties['samaccountname'] -and ($usrTmp.Properties['samaccountname'][0].Length -ne 0))
        {
            $SamAccountName = $usrTmp.Properties['samaccountname'][0].replace("$", "")

            $Description = $null

            if ($usrTmp.Properties['description'] -and ($usrTmp.Properties['description'][0].Length -ne 0)) {
	            $Description = $usrTmp.Properties['description'][0]
            }

            New-Object PSObject -Property @{
                SAMAccountName = $SamAccountName
                Description = $Description    
            }
        }
    }
}

Function Get-UserMembership
{
<#
.SYNOPSIS

Will get details about specified user

Author: Evan Peña
License: GPLv3
Required Dependencies: Domain Account
Optional Dependencies: None
 
.DESCRIPTION

Will get details about specified user. Details will include group membership, 
account lockout, etc.

.PARAMETER DCHostName

Specifies the domain controller that will be used to esablish an LDAP connection.

.PARAMETER LDAPSession

Uses an existing LDAP session obtained from New-LDAPSession

.PARAMETER UserName

Specifies user name you want details about. Accepts single username, array of usernames, or a list piped to it

.EXAMPLE

Get-UserMembership -DCHostName ServerDC.contoso.local -UserName evan.pena

.EXAMPLE

Get-UserMembership -LDAPSession $domain -UserName evan.pena | Format-Table -Wrap -Proper Name,Value

.EXAMPLE

Get-UserMembership -LDAPSession $domain -UserName evan.pena | Format-List

Description
-----------
If you want to expand table to include all contents

.EXAMPLE

gc UserNameList.txt | Get-UserMembership -LDAPSession $domain

Description
-----------
Will take contenst of username list and get user information from all users in the list
#>
  [CmdletBinding(DefaultParameterSetName='LDAPSessionSet')]
	Param
       (
		 [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [ValidateNotNullOrEmpty()]
         [String]
         $DCHostName,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet")]
         [Management.Automation.PSCredential]
         [Management.Automation.CredentialAttribute()]
         $Credential,
		 
		 [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet")]		 
         [ValidateNotNullOrEmpty()]
         [DirectoryServices.DirectoryEntry]
         $LDAPSession,

         [Parameter(Mandatory = $True, ParameterSetName="DomainInfoSet", ValueFromPipeLine=$True)]
         [Parameter(Mandatory = $True, ParameterSetName="LDAPSessionSet", ValueFromPipeLine=$True)]
		 [ValidateNotNullOrEmpty()]
		 [String[]]
         $UserName
		)
	Process {
		if ($PSboundparameters["DCHostName"]) {
			$domain = new-object DirectoryServices.DirectoryEntry("LDAP://$DCHostName",$Credential.UserName, $Credential.GetNetworkCredential().Password)
		}
		else {
			$domain = $LDAPSession
		}
		
		$dsLookFor = new-object System.DirectoryServices.DirectorySearcher($domain)
		$dsLookFor.ClientTimeout = "00:00:05"
		$dsLookFor.ServerTimeLimit = "00:00:05"		
		$allUserData = New-Object HashTable	
	
		foreach ($user in $UserName) {
			$lstUsr = ""
			$usrTmp = ""
			$dsLookFor.filter = "(&(objectClass=person)(samaccountname=$user))"
			$dsLookFor.PageSize = 1000;
			$dsLookFor.SearchScope = "subtree"; 
			$lstUsr = $dsLookFor.findall()
			if ($lstUsr -ne "") {
				foreach ($usrTmp in $lstUsr) 
				{
					$allUserData.Clear()
					$Groups = Get-UserGroups -GroupList $usrTmp.Properties['memberof']
					$Groups = $Groups -join ","
					$allUserData.Add("memberof", $Groups)
					
					$properties = $usrTmp.Properties.GetEnumerator() | select name
					foreach ($i in $properties) {				
						if ($i.name -eq "samaccountname") {
							$allUserData.Add("Account", $usrTmp.Properties['samaccountname'][0])
						}
						elseif ($i.name -eq "name") {					
							$allUserData.Add("Name", $usrTmp.Properties['name'][0])
						}		
						elseif ($i.name -eq "samaccountname") {
							$allUserData.Add("Account", $usrTmp.Properties['samaccountname'][0])
						}
						elseif ($i.name -eq "lockouttime") {
							$lockOutTime = ConvertTo-Date -TimeStamp $usrTmp.Properties['lockouttime'][0]
							$allUserData.Add("LockoutTime", $lockOutTime)
						}
						elseif ($i.name -eq "accountexpires") {
							$accountExpires = ConvertTo-Date -TimeStamp $usrTmp.Properties['accountexpires'][0]
							$allUserData.Add("AccountExpires", $accountExpires)
						}
						elseif ($i.name -eq "pwdlastset") {
							$pwdlastset = ConvertTo-Date -TimeStamp $usrTmp.Properties['pwdlastset'][0]
							$allUserData.Add("PwdLastSet", $pwdlastset)
						}
						elseif ($i.name -eq "whenchanged") {
							$allUserData.Add("WhenChanged", $usrTmp.Properties['whenchanged'][0])
						}
						elseif ($i.name -eq "scriptpath") {
							$allUserData.Add("ScriptPath", $usrTmp.Properties['scriptpath'][0])
						}
						elseif ($i.name -eq "lastlogon") {
							$LastLogon = ConvertTo-Date -TimeStamp $usrTmp.Properties['lastlogon'][0]
							$allUserData.Add("LastLogon", $LastLogon)
						}
						elseif ($i.name -eq "lastlogoff") {
							$lastLogOff = ConvertTo-Date -TimeStamp $usrTmp.Properties['lastlogoff'][0]
							$allUserData.Add("LastLogoff", $lastLogOff)
						}
					}
				}			
				$allUserData
				"`n"
			}	
		}
	}
}

Function ConvertTo-Date {
    Param (
        [Parameter(ValueFromPipeline=$true,mandatory=$true)]$TimeStamp
    )
    
	process {
		$lngValue = $TimeStamp
		if(($lngValue -eq 0) -or ($lngValue -gt [DateTime]::MaxValue.Ticks)) {
			$AcctExpires = "<Never>"
		} else {
			$Date = [DateTime]$lngValue
			$AcctExpires = $Date.AddYears(1600).ToLocalTime()
		}
		$AcctExpires.ToString()
	}
}

Function Get-UserGroups
{
	Param (
			[Parameter(ValueFromPipeline=$true,mandatory=$true)]$GroupList
		)
	$allGroups = @()
		foreach ($group in $GroupList)
		{
			$tmpGroup = $group.split(',')[0]
			$tmpGroup = $tmpGroup.replace('CN=','')
			$allGroups += $tmpGroup
		}
	$allGroups
		
}