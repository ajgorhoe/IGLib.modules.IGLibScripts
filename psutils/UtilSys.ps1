


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



function IsLinux()
{
	if ($IsLinux) {
		return $true;
	} else {
		return $false;
	}
}

function IsWindows()
{
	if ($env:OS -like 'Windows*') {
		return $true;
	} else {
		return $fale;
	}
}


function GetTotalMemory()
{
	$memoryInfo = Get-CimInstance -ClassName CIM_OperatingSystem
	return $memoryInfo.TotalVisibleMemorySize
}


function GetFreeMemory()
{
	$memoryInfo = Get-CimInstance -ClassName CIM_OperatingSystem
	return $memoryInfo.FreePhysicalMemory
}

function GetCpuUsage()
{
	return (Get-CimInstance -ClassName CIM_Processor).LoadPercentage;
}





            #############################
            #                           #
            #    Process Information    #
            #                           #
            #############################


<#

#>


function GetProcCpuWin($num = 20)
{
	Get-Counter '\Process(*)\ID Process','\Process(*)\% Processor Time' -ErrorAction SilentlyContinue |
    ForEach-Object {
    $_.CounterSamples |
      Where-Object InstanceName -NotMatch '^(?:idle|_total|system)$' |
      Group-Object {Split-Path $_.Path} |
      ForEach-Object {
        [pscustomobject]@{
          ProcessName = $_.Group[0].InstanceName
          ProcessId = $_.Group |? Path -like '*\ID Process' |% RawValue
          CPUCooked = $_.Group |? Path -like '*\% Processor Time' |% CookedValue
        }
      } |Sort-Object CPUCooked -Descending |
         Select-Object -First $num -Property *,@{Name='CPUPercentage';Expression={'{0:P}' -f ($_.CPUCooked / 100 / $env:NUMBER_OF_PROCESSORS)}} -ExcludeProperty CPUCooked
  }
}



function GetProcessCPUUsage()
{


# Get all processes
$allProcesses = Get-Process
# Create a dictionary to store process objects with process ID as the key
$processDictionary = @{}
# Populate the dictionary
foreach ($process in $allProcesses) {
    $processDictionary[$process.Id] = $process
}
# Sleep for one second to measure CPU time over an interval
Start-Sleep -Seconds 1

# Get processes and calculate CPU usage percentage
$Processes = Get-Process | sort CPU -Descending | select -First 10 | ForEach-Object {
	Write-Output "Name: $_.Name"
	Write-Output "Id: $_.Id"
	Write-Output "Current CPU: $_.CPU"
    # $_ | Add-Member -MemberType NoteProperty -Name 'CPUPercentage' -Value (($_.CPU - $processDictionary[$_.Id].CPU) * 100) -PassThru
	
	$_ | Add-Member -MemberType NoteProperty -Name 'CPUPercentage' -Value (($_.CPU /2) * 100) -PassThru
}
$Processes | sort CPUPercentage -Descending | Select-Object Name, Cpu, CPUPercentage
#  | select -First 10


$sampleProc = $allProcesses[0]
Write-Host "Sample process: "
Write-Host "Name:"   $sampleProc.Name
Write-Host "Id: "    $sampleProc.Id
Write-Host "CPU:  "  $sampleProc.CPU
$dictProc = $processDictionary[$sampleProc.Id]
Write-Host "Corresponding process from dictionary: "
Write-Host "Name:"   $dictProc.Name
Write-Host "Id: "    $dictProc.Id
Write-Host "CPU:  "  $dictProc.CPU


}





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
.Remarks
Platform information on 
.Example
GetProc "explore"
  - returns all processes that have "explore" in their name.
GetProc -SortCpu -First 20
  - returns the first 20 processes sorted by the CPU property in descending order.
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
	if ($null -ne $NameContains)
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
		if ($null -eq $First)
		{
			$First = 20
			# Write-Host "  First (because: SortCpu):         $First"
		}			
	}
	if ($null -ne $Last -and $Last -gt 0)
	{
		$ret = $ret | Select-Object -Last $Last
	}
	if ($null -ne $First -and $First -gt 0)
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
This function returns computer's devices. Various filtering and sorting options
can be applied, whih includes requiring the name or class to include a certain
string, or returning only devices that are probably USB devices.
See also .Synopsis.
.Parameter NameContains
If not $null: Only devices that contain $NameContains in their Name parameters
are returned.
.Parameter ClassContains
If not $null: Only devices that contain $ClassContains in their Name parameters
are returned.
.Parameter First
If specified then only the first $First entries are returned.
.Parameter Last
If specified then only the first $Last entries are returned. If parameter First is
also specidied then this parameter has precee\edence over it.
.Parameter SortName
Switch. Returned devices are sorted by the Name property.
.Parameter SortClass
Switch. Returned devices are sorted by the Class property. If both this switch 
and the SortName are specified then outer sort is by class and inner is by name.
.Parameter All
Switch. If on then also devices that are not plugged in are listed (those
whose Status property is not "OK").
.Parameter TableFormat 
If ths switch is specified ($true) then returned records are formatted as a table.
.Parameter OnlyUsbDevices
Switch. If on then only devices that are probably USB devices are listed.
#>
function GetDevices($NameContains = $null, $ClassContains = $null, 
	$First = $null, $Last = $null, 
	[switch] $SortName, [switch] $SortClass, 
	[switch] $All, [switch] $TableFormat,
	[switch] $OnlyUsbDevices)
{
	$ret = Get-PnpDevice
	if ($OnlyUsbDevices)
	{
		# Return is limited to USB debices
		$ret = $ret | Where-Object { 
			$_.InstanceId -match 'USB' -or
			$_.Class -match 'USB'
		}
	}
	if (-not $All)
	{
		$ret = $ret | Where-Object { $_.Status -eq "OK" }
	}
	if ($null -ne $NameContains)
	{
		$ret = $ret | Where-Object { $_.Name `
			-match "$NameContains" }
	}
	if ($null -ne $ClassContains)
	{
		$ret = $ret | Where-Object { $_.Class `
			-match "$ClassContains" }
	}
	if ($SortName)
	{
		if ($SortClass)
		{
			$ret = $ret | Sort-Object Class, Name
		} else 
		{
			$ret = $ret | Sort-Object Name
		}
	} elseif ($SortClass)
	{
		$ret = $ret | Sort-Object Name
	}

	if ($null -ne $Last -and $Last -gt 0)
	{
		$ret = $ret | Select-Object -Last $Last
	}
	if ($null -ne $First -and $First -gt 0)
	{
		$ret = $ret | Select-Object -First $First
	}
	if ($TableFormat)
	{
		$ret = $ret | Format-Table
	}
	return $ret;
}



<#
.Synopsis
Gets a list of USB devices on the current computer.
.Description
The same as GetDevices(), except that only the devices that are most likely 
USB devices are returned (this method calls the GetDevices() to do the job).
This method has the same parameters as GetDevices, except the $OnlyUsbDevices, 
which is not a parameter because this switch is always on.
See also .Synopsis.
.Remarks
For meanning of parameters, see GetDevices().
#>

function GetUsbDevices($NameContains = $null, $ClassContains = $null, 
	$First = $null, $Last = $null, 
	[switch] $SortName, [switch] $SortClass, 
	[switch] $All, [switch] $TableFormat )
{
	# if ($true)
	# {
	# 	Write-Host "Function GetUsbDevices called:"
	# 	Write-Host "  NameContains:  $NameContains"
	# 	Write-Host "  ClassContains: $ClassContains"
	# 	Write-Host "  TableFormat:   $TableFormat"
	# 	Write-Host "  First:         $First"
	# 	Write-Host "  Last:          $Last"
	# 	Write-Host "  SortName:      $SortName"
	# 	Write-Host "  SortClass:     $SortClass"
	# 	Write-Host "  All:           $All"
	# 	Write-Host "  TableFormat:   $TableFormat"
	# }
	$ret = $null
	$ret = GetDevices `
			-NameContains: $NameContains -ClassContains: $ClassContains `
			-First: $First -Last: $Last `
			-SortName: $SortName  -SortClass: $SortClass `
			-All: $All `
			-TableFormat: $TableFormat `
			-OnlyUsbDevices: $true 
			
	return $ret
}



<#
.Synopsis
Gets a list of connected USB controllers.
.Description
See .Synopsis.
.Parameter All
If $true then all information on controllers is included in the list. If $false
then only the basic information is provided.
.Parameter TableFormat 
If ths switch is specified ($true) then returned records are formatted as a table.
#>
function GetUsbControllers([switch] $All, [switch] $TableFormat)
{
	$ret = Get-WmiObject -Query "SELECT * FROM Win32_USBController"
	if (-not $All)
	{
		$ret = $ret | Where-Object { $_.Status -eq "OK" }
		$ret = $ret |
			Select-Object `
			Name, Description, `
			Manufacturer, `
			Status, `
			Caption, `
			PNPDeviceID `
			#Manufacturer `
	}
	if ($TableFormat)
	{
		$ret = $ret | Format-Table
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
	return $entries 
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
	$ret = $null
	
	$ret = $(GetAvailableWifiNetworks)
	# ToDo: use th line below to define th return value!
	return $ret | Out-GridView -Title 'Available Wi-Fi networks'
}




