


            #######################
            #                     #
            #    Web Utilities    #
            #                     #
            #######################

# Remarks:
# Useful snippets in PowerShell:
# https://techexpert.tips/powershell/powershell-display-connected-usb-storage-devices/




            ######################
            #                    #
            #    System state    #
            #                    #
            ######################


<#
.Synopsis
Gets a list of running processes.
.Description
See .Synopsis.
.Notes
See .Synopsis.
.Parameter NameContains
If specified (not $null) then only those processes are listed that contain 
the $NameContains in their process name. This parameter can also be specified as
the first positional parameter.
.Parameter First
If specified then only the first $First entries are returned.
.Parameter Last
If specified then only the first $Last entries are returned. If parameter First is
also specidied then this parameter has precee\edence over it.
.Parameter SortCpu
If this switch is specified ($true) then returned records are sorted by the CPU property.
.Parameter SortProcessName
If ths switch is specified ($true) then returned records are sorted by the
ProcessName property.
.Parameter TableFormat 
If ths switch is specified ($true) then returned records are formatted as a table.
.Remarks
This dunction returns a list of processes.
.Example
GetProc ""
#>
function GetProc($NameContains=$null, $First = $null,
	$Last = $null, [switch] $SortCpu, [switch] $SortProcessName, 
	[switch] $TableFormat)
{
	# if ($true)
	# {
		# Write-Host "Function GetProcesses called:"
		# Write-Host "  NameContains:  $NameContains"
		# Write-Host "  TableFormat:   $TableFormat"
		# Write-Host "  First:         $First"
		# Write-Host "  Last:          $Last"
		# Write-Host "  SortCpu:       $SortCpu"
	# }
	$ret = Get-Process
	if ($NameContains -ne $null)
	{
		$ret = $ret | Where-Object { $_.ProcessName `
			-match "$NameContains" }
	}
	if ($SortProcessName)
	{
		$ret = $ret | Sort-Object ProcessName
	}
	if ($SortCpu)
	{
		$ret = $ret | Sort-Object CPU -Descending
		if ($First -eq $null)
		{
			$First = 20
			# Write-Host "  First (because: SortCpu):         $First"
		}			
	}
	if ($Last -ne $null -and $Last -gt 0)
	{
		$ret = $ret | Select-Object -Last $Last
	}
	if ($First -ne $null -and $First -gt 0)
	{
		$ret = $ret | Select-Object -First $First
	}
	if ($TableFormat)
	{
		$ret = $ret | Format-Table
	}
	return $ret;
}


            ############################
            #                          #
            #    Hardware Utilities    #
            #                          #
            ############################


<#
.Synopsis
Gets a list of computer's storage drives.
.Description
See .Synopsis.
.Parameter All
If $true then all original information on computer drives is included in the returned 
value.
.Parameter TableFormat
If true then function return is formatted as a table
#>
function GetDrives([switch] $All, [switch] $TableFormat)
{
	$ret = [System.IO.DriveInfo]::getdrives()
	if (-not $All)
	{
		$ret = $ret |
		Select-Object -Property RootDirectory, IsReady, DriveType, DriveFormat,
		@{
			label='TotalSizeGB'
			expression={($_.TotalSize/1GB).ToString('F2')}
		}, 
		@{
			label='FreeSpaceGB'
			expression={($_.AvailableFreeSpace/1GB).ToString('F2')}
		}, 
		@{
			label='FreeSpacePercent'
			expression={(100*$_.AvailableFreeSpace/$_.TotalSize).ToString('F2') + "%"}
		}
		# Name, 
	}
	if ($TableFormat)
	{
		$ret = $ret | Format-Table
	}
	return $ret;
}



<#
.Synopsis
Gets a list of computer's devices.
.Description
See .Synopsis.
.Parameter All
If $true then information on all deviced is returned, even those whose Status 
property is not OK.
#>
function GetDevices([switch] $All)
{
	$ret = Get-PnpDevice
	if (-not $All)
	{
		$ret = $ret | Where-Object { $_.Status -eq "OK" }
	}
	return $ret;
}



<#
.Synopsis
Gets a list of connected USB devices.
.Description
See .Synopsis.
.Parameter Verbose
If $true then complete information on devices is included in the list. If $false
then only the basic information is included.
#>
function GetUsbDevices([switch]$Verbose)
{
	if ($Verbose)
	{
		$ret = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB' } | Format-List
	} else
	{
		$ret = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB' }
	}
	return $ret;
}


<#
.Synopsis
Gets a list of connected USB controllers.
.Description
See .Synopsis.
.Parameter Verbose
If $true then all information on controllers is included in the list. If $false
then only the basic information is provided.
#>
function GetUsbControllers($Verbose = $False)
{
	if ($Verbose)
	{
		$ret = Get-WmiObject -Query "SELECT * FROM Win32_USBController"
	} else
	{
		$ret = Get-WmiObject -Query "SELECT * FROM Win32_USBController" |
			Select-Object `
			Name, Description, `
			Manufacturer, `
			Status `
			| Format-List
			#Caption, `
			#Manufacturer `
			#PNPDeviceID, `
	}
	return $ret;
}




            #########################
            #                       #
            #    Wi-Fi utilities    #
            #                       #
            #########################

# Remarks:
# Wi-Fi utilities are for Windows platforms.
# See e.g.:
# https://www.windowscentral.com/how-determine-wi-fi-signal-strength-windows-10#wifi_signal_strength_powershell
# https://woshub.com/check-wi-fi-signal-strength-windows/


######    Wi-Fi connections


<#
.Synopsis
Returns a string containing Wi-Fi interfaces connected as string.
.Description
See Synopsis.
#>
function GetWifiInterfaceStr()
{
	return $(netsh wlan show interfaces)
}


<#
.Synopsis
Returns the signal strength of the Wi-Fi network to which the current host is
connected (if any), expressed as percentage string (e.g. "85%").
.Description
Returns the signal strength of the Wi-Fi network to which the current host is
connected (if any).
This method does not take any parameters.
#>
function GetWifiStrengthPercentStr()
{
	$ret = (netsh wlan show interfaces) -Match '^\s+Signal' -Replace '^\s+Signal\s+:\s+'
	return $ret
}


<#
.Synopsis
Returns the signal strength of the Wi-Fi network to which the current host is
connected (if any), expressed as percentage (as floating point number of
type double, e.g. 85).
.Description
See .Synopsis.
#>
function GetWifiStrengthPercent()
{
	$strengthPercentStr = $(GetWifiStrengthPercentStr)
	$strengthPercent = $strengthPercentStr.replace('%','')
	return [double]$strengthPercent
}

<#
.Synopsis
Returns the signal strength of the Wi-Fi network to which the current host is
connected (if any), expressed as double number between 0 and 1.
.Description
See .Synopsis.
#>
function GetWifiStrength()
{
	return $(GetWifiStrengthPercent) / 100.0
}



<#
.Synopsis
Displays a warning nnotification if the Wi-Fi signal strength is below 
certain limit.
.Description
See .Synopsis.
.Parameter RequiredStrengthPercent
The required minimal signal strength, in per cent, below which the warning
notifiction will be displayed. Default is 80.
#>
function WifiDisplayWeakWarning($RequiredStrengthPercent=80)
{
	$strength = $(GetWifiStrengthPercent)
	
	If ($strength -le $RequiredStrengthPercent) {
		Add-Type -AssemblyName System.Windows.Forms
		$global:balmsg = New-Object System.Windows.Forms.NotifyIcon
		$path = (Get-Process -id $pid).Path
		$balmsg.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
		$balmsg.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
		$balmsg.BalloonTipText = "The Wi-Fi signal strength is less than $($RequiredStrengthPercent)%."
		$balmsg.BalloonTipTitle = "Attention $($Env:USERNAME)!"
		$balmsg.Visible = $true
		$balmsg.ShowBalloonTip(10000)
	}
}



######    Wi-Fi networks (detectable)

<#
.Synopsis
Returns information on available Wi-Fi networks in string form.
.Description
See .Synopsis.
#>
function GetAvailableWifiNetworksStr()
{
	$ret=netsh wlan show networks mode=bssid
	return $ret
}

<#
.Synopsis
Returns an array of available Wi-Fi networks information.
.Description
See .Synopsis.
#>
function GetAvailableWifiNetworks()
{
	$entries=@()
	$date=Get-Date
	$cmdRes=netsh wlan show networks mode=bssid
	$n=$cmdRes.Count
	For($i=0; $i -lt $n; $i++)
	{
		If($cmdRes[$i] -Match '^SSID[^:]+:.(.*)$')
		{
			$ssid=$Matches[1]
			$i++
			$bool=$cmdRes[$i] -Match 'Type[^:]+:.(.+)$'
			$Type=$Matches[1]
			$i++
			$bool=$cmdRes[$i] -Match 'Authentication[^:]+:.(.+)$'
			$authent=$Matches[1]
			$i++
			$bool=$cmdRes[$i] -Match 'Cipher[^:]+:.(.+)$'
			$chiffrement=$Matches[1]
			$i++
			While($cmdRes[$i] -Match 'BSSID[^:]+:.(.+)$')
			{
				$bssid=$Matches[1]
				$i++
				$bool=$cmdRes[$i] -Match 'Signal[^:]+:.(.+)$'
				$signal=$Matches[1]
				$i++
				$bool=$cmdRes[$i] -Match 'Type[^:]+:.(.+)$'
				$radio=$Matches[1]
				$i++
				$bool=$cmdRes[$i] -Match 'Channel[^:]+:.(.+)$'
				$Channel=$Matches[1]
				$i=$i+2
				$entries+=[PSCustomObject]@{ssid=$ssid;Authentication=$authent;Cipher=$chiffrement;bssid=$bssid;signal=$signal;radio=$radio;Channel=$Channel}
			}
		}
	}
	$cmdRes=$null
	$entries 
	# | Out-String
}


<#
.Synopsis
Displays information on available Wi-Fi networks in a grid view.
.Description
See .Synopsis.
#>
function WifiDisplayAwailableGridView() 
{
	$ret = $(GetAvailableWifiNetworks)
	$ret | Out-GridView -Title 'Available Wi-Fi networks'
}



