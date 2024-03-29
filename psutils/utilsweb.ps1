
#!/usr/bin/env pwsh

# Tis PowerShell script adds some web-related utilities to PowerShell.

# Part of the Investigative Generic Library (IGLib).
# https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git




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



