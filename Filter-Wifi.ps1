#region Log-It Function
<#
.SYNOPSIS
  Removes Wifi networks from device.
.DESCRIPTION
  Hides specified Wifi networks from users device. Best used in envirornments without GPO enforcement on Wifi.
.PARAMETER <Parameter_Name>
  -enabled (Mandatory)
        Available options : $true, $false  
.OUTPUTS
  Log file stored in C:\LDlogs\$LogName.html>
.NOTES
  Version:        1.0
  Author:         Thomas Dobson
  Creation Date:  3/7/2018
  Change Date:    3/6/2017
  Purpose/Change: Initial Creation
  
.EXAMPLE
  Filter-Wifi -enabled $false
  Filter-Wifi -enabled $true
#>
function Filter-Wifi {
 
#Parameters
    [CmdletBinding()]
    Param (
    [Parameter(Mandatory = $True, Position = 0, HelpMessage = "Turn on Sharp Wifi Filtering")]
    [Bool]$enabled
    )

#Variables
    $Global:logfile = "Sharp Wifi Filter"
    $wirelessFilterArray = 
    "SharpTeam",
    "Sharp_Guest",
    "UMD",
    "cisco",
    "VoIP-net"

#Declaring Functions

#Scans for Available Networks. Outputs a PSObject.
Function scanNetworks {
    #function trimmed down from https://gallery.technet.microsoft.com/scriptcenter/Wireless-networks-scanner-938fb966#content
    $interface_name_text = "Interface name";
    $ssid_text           = "SSID";
    $network_type_text   = "Network type";
    $bssid_text          = "BSSID";

    function getValueByName ( $inputText, $nameString ) {
        $value = "";
        if ([regex]::IsMatch($inputText,"\b$nameString\b","IgnoreCase")) {
        $value = ([regex]::Replace($inputText,"^[^:]*: ","")); 
        }
        return $value.Trim();
    }


    if  ([int](gwmi win32_operatingsystem).Version.Split(".")[0] -lt 6) {
        throw "This script works on Windows Vista or higher.";
    }

    if ((gsv "wlansvc").Status -ne "Running" ) {
        throw "WLAN AutoConfig must be running.";
    }

    $activeNetworks = @();
    $rowNumber = -1;
    $interfaceName = "";

    netsh wlan show network mode=bssid | % {
	
        $ifName = getValueByName $_ $interface_name_text;
        if ($ifName.Length -gt 0) {
            $interfaceName = $ifname;
            return;
        }
	
        $ssid = getValueByName $_ $ssid_text;
        if ($ssid.Length -gt 0) {
            $row = New-Object PSObject -Property @{
                InterfaceName = $interfaceName;
                SSID=$ssid 
                NetworkType=""
                BSSID=""

            }
            $rowNumber+=1;
            $ActiveNetworks += $row;
            return;
        }
        $bssid = getValueByName $_ $bssid_text;
        if ($bssid.Length -gt 0) {
            $ActiveNetworks[$rowNumber].BSSID = $bssid;
            return;
        }
        $network_type = getValueByName $_ $network_type_text;
        if ($network_type.Length -gt 0) {
            $ActiveNetworks[$rowNumber].NetworkType = $network_type;
            return;
        }

    };

    if ($ActiveNetworks.Count -gt 0) {
    return $activeNetworks | Select-Object BSSID, 
							    SSID, 
					    InterfaceName | Sort-Object Signal -Descending
    } else { 
    Write-Warning "`n No active networks.`n"; 
    }

}

#If a network is detected, and part of the $wirelessFilterArray, at netsh block filter will be added for it.
function detectAndFilterWifi {

    $availableNetworks = scanNetworks
    foreach ($network in $wirelessFilterArray) {
        If (($availableNetworks | select SSID) -match $network) {
            Log-It "INFORM" "$network network detected. Applying $action filter via Netsh." $logfile
            $result = netsh wlan $action filter permission=block ssid=”$network” networktype=infrastructure
                   
        }
    }
}

#For Each network in the $wirelessFilterArray, at netsh block filter will be removed.
function disableFilters {
    foreach ($network in $wirelessFilterArray) {
        Log-It "INFORM" "Applying $action filter via Netsh to $network." $logfile
        $result = netsh wlan $action filter permission=block ssid=”$network” networktype=infrastructure
    }
}

#Doublecheck the targeted filters were applied. Network wont be detected if filter applied correctly.
function verifiyFiltersApplied {

    $filtersApplied = $true

    foreach ($network in $wirelessFilterArray) {
        for ($i = 0; $i -lt 5; $i++) {
            $availableNetworks = scanNetworks
            If (!(($availableNetworks | select SSID) -match $network)) {
                Log-It "SUCCESS" "$network network is not detected. Filter Applied Succesfully." $logfile
                break
            } else {
                Log-It "WARN" "$network network still detected. Filter failed to apply filter. Waiting for: $($i * 5) seconds." $logfile
                $filtersApplied = $false
                sleep -Seconds 5
            }
        }
    }

    if (!$filtersApplied){
        Log-It "FATAL" "Some Filters Failed to Apply." $logfile 
    } else {
        Log-It "SUCCESS" "All Filters were applied." $logfile 
    }
}

#Checks for existing filters that match the networks specified in $wirelessFilterArray.
function CheckForExistingFilters {
    $results = netsh.exe wlan show filter permission="block"
    $filters = 0
    foreach ($network in $wirelessFilterArray) {
        if ($results -match $network) {
            Log-It "SUCCESS" "$network already detected in existing filters." $logfile                
        } else {
            Log-It "WARN" "The $network filter is missing" $logfile
            $filters++
        }

    }
    return $filters
}


#region Log-It Function
<#
.SYNOPSIS
  Function to write logs to HTML file for general error handling @ Sharp HealthCare.
.DESCRIPTION
  Standardized Log Writting Function for Sharp HealthCare
.PARAMETER <Parameter_Name>
  -Level (Mandatory)
        Available Levels : INFORM WARN ERROR FATAL DEBUG SUCCES
  -Message (Mandatory)
        String containing Message to write to log
  -LogName (Mandatory)
        Name for logfile being generated. Default Directory c:\ldlogs
  -ComputerName (Optional)
        Specify Remote HostName. Current HostName will be used if not provided.   
.OUTPUTS
  Log file stored in C:\LDlogs\$LogName.html>
.NOTES
  Version:        1.0
  Author:         Thomas Dobson
  Creation Date:  12/12/2017
  Change Date:    3/6/2017
  Purpose/Change: Improved Logging. Bug Fixes.
  
.EXAMPLE
  Log-It "WARN" "INSTALL FAILED. UNABLE TO WRITE TO DIRECTORY""MyInstaller"
  Log-IT "SUCCESS" "File Copied SuccessFully." "MyInstaller" "IS1713922"
  Log-IT "FATAL" "This Error Happened" "MyScript" -intializeNewLog $true
#>
Function Log-It
{
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = "Log Level")]
		[ValidateSet("INFORM", "WARN", "ERROR", "FATAL", "DEBUG", "SUCCESS")]
		[string]$Level = "INFORM",
		[Parameter(Mandatory = $true, Position = 1, HelpMessage = "Message to be written to the log")]
		[string]$Message,
		[Parameter(Mandatory = $true, Position = 2, HelpMessage = "Log file location and name")]
		[string]$LogName,
		[Parameter(Mandatory = $false, Position = 4, HelpMessage = "Target PC Asset Tag / Hostname")]
		[Bool]$intializeNewLog = $false,
		[Parameter(Mandatory = $false, Position = 3, HelpMessage = "Target PC Asset Tag / Hostname")]
		[String]$computerName
	)
	
	#region variables
	$initiatingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
	
	$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$logName</title>
<link rel="stylesheet" href="C:\LDLogs\Css\logstyle.css">
</head>
<body>
</body></html>
"@
	
	$css = @"
/*v1.1*/

#INFORM{
  font: 20px;
  font-weight: bolder;
  color: BLACK;
}

#WARN{
  font: 20px;
  font-weight: bolder;
  color: ORANGE;
}

#ERROR{
  font: 20px;
  font-weight: bolder;
  color: RED;
}
#FATAL{
  font: 20px;
  font-weight: bolder;
  color: RED;
}

#DEBUG{
  font: 20px;
  font-weight: bolder;
  color: BLUE;
}

#SUCCESS{
  font: 20px;
  font-weight: bolder;
  color: GREEN;
}

#header{
  font-size: 1.5em;
  font-weight: bold;
}
"@
	
	$Stamp = (Get-Date).toString("HH:mm:ss MM/dd/yyyy")
	
	If (!$computerName)
	{
		$computerName = $env:computername
	}
	
	$logPath = "\\$computerName\C$\LDLogs\$LogName.html"
	$CSSPath = "\\$computerName\C$\LDLogs\css\logstyle.css"
	
	#endregion
	
	Function AppendToHTMLLog
	{
		
		$htmlClosure = "</body></html>"
		$htmlHeader = "<p id=`"header`">[$Stamp] $logName Initialied by $initiatingUser</p>"
		$htmlSpacers = "<p>****************************************************************************</p>"
		$htmlLogger = "[$Stamp]<span id=`"$level`">&nbsp&nbsp$level&nbsp&nbsp</span> $message<br>"
		
		$rawLog = Get-Content $logPath
		if ($intializeNewLog)
		{
			$rawLog.Replace("</body></html>", "$htmlSpacers$htmlHeader$htmlSpacers$htmlLogger$htmlClosure") | Out-File $logPath
		}
		else
		{
			$rawLog.Replace("</body></html>", "$htmlLogger$htmlClosure") | Out-File $logPath
		}
		
	}
	
	#Generate New CSS
	function createCSS
	{
		New-Item -Path "\\$computerName\C$\LDLogs\CSS" -Name "logstyle.css" -ItemType File
		$css | Out-File $CSSPath
	}
	
	
	#If specified logfile doesn't exist; create it.
	If (!(Test-Path($logPath)))
	{
		New-Item -Path "\\$computerName\C$\LDLogs" -Name "$LogName.html" -ItemType File
		$html | Out-File $logPath
	}
	
	#check logfile versioning. Remove old logs. Generate / Replace CSS.
	$cssExists = Test-Path($CSSPath)
	if ($cssExists)
	{
		
		$cssversion = (Get-Content C:\ldlogs\css\logstyle.css -First 1).Substring(3, 3)
		$currentVersion = "1.1"
		if ($cssversion -ne $currentVersion)
		{
			Remove-Item -Path $CSSPath -Force
			createCSS
		}
		
	}
	else
	{
		createCSS
	}
	
	#Write to Logs
	If ($logPath)
	{
		
		Switch ($Level)
		{
			"INFORM" { AppendToHTMLLog }
			"WARN" { AppendToHTMLLog }
			"ERROR" { AppendToHTMLLog }
			"FATAL" { AppendToHTMLLog }
			"DEBUG" { AppendToHTMLLog }
			"SUCCESS" { AppendToHTMLLog }
		}
	}
	Else
	{
		Write-Output $Line
	}
	
}
#endregion


    #Main
        Log-It "INFORM" "Initiating Sharp Wifi Filter Logfile" $logfile -intializeNewLog $true
        if ($enabled) {
            if ((CheckForExistingFilters) -ge $wirelessFilterArray.Count) {
                $action = "add"
                detectAndFilterWifi
                verifiyFiltersApplied
            } else {
                Log-It "SUCCESS" "All filters already applied. Ending Script" $logfile
            }

        } else {
            $action = "delete"
            If((CheckForExistingFilters) -ge $wirelessFilterArray.Count) {
                Log-It "SUCCESS" "No Filters Present." $logfile
            } else {
                disableFilters
                If((CheckForExistingFilters) -ge $wirelessFilterArray.Count) {
                    Log-It "SUCCESS" "All Filters Deleted Successfully" $logfile
                } else {
                    Log-It "FATAL" "All Filters Deleted Successfully" $logfile
                }
            }
        }


}

<# TROUBLESHOOTING AND TESTING COMMANDS

netsh.exe wlan add filter permission=block ssid=”SharpTeam” networktype=infrastructure
netsh wlan add filter permission=block ssid=”UMD” networktype=infrastructure
netsh wlan add filter permission=block ssid=”VoIP-net” networktype=infrastructure
netsh wlan add filter permission=block ssid=”cisco” networktype=infrastructure
netsh wlan add filter permission=block ssid=”Sharp_Guest” networktype=infrastructure

netsh wlan delete filter permission=block ssid=”SharpTeam” networktype=infrastructure
netsh wlan delete filter permission=block ssid=”UMD” networktype=infrastructure
netsh wlan delete filter permission=block ssid=”VoIP-net” networktype=infrastructure
netsh wlan delete filter permission=block ssid=”cisco” networktype=infrastructure
netsh wlan delete filter permission=block ssid=”hpsetup” networktype=infrastructure

#>