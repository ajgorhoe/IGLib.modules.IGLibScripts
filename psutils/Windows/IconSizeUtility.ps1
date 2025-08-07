Add-Type -AssemblyName System.Windows.Forms

# Size mappings
$desktopSizes = @{ Small = 16; Medium = 32; Large = 48; ExtraLarge = 64 }
$taskbarSizes = @{ Small = 0; Medium = 1; Large = 2 }

function Get-CurrentDesktopSize {
    try {
        $value = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" -Name "IconSize"
        return ($desktopSizes.GetEnumerator() | Where-Object { $_.Value -eq $value }).Name
    } catch {
        return "Medium"
    }
}

function Get-CurrentTaskbarSize {
    try {
        $value = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSi"
        return ($taskbarSizes.GetEnumerator() | Where-Object { $_.Value -eq $value }).Name
    } catch {
        return "Medium"
    }
}

function IsTaskbarSizeUnsupported {
    $osVersion = [System.Environment]::OSVersion.Version
    return ($osVersion.Major -eq 10 -and $osVersion.Build -ge 26000)
}

function Set-DesktopIconSize {
    param($value, $hive = "HKCU")
    $regPath = "Registry::$hive\Software\Microsoft\Windows\Shell\Bags\1\Desktop"

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    $existing = Get-ItemProperty -Path $regPath -Name "IconSize" -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-ItemProperty -Path $regPath -Name "IconSize" -Value $value -PropertyType DWord -Force | Out-Null
    } else {
        Set-ItemProperty -Path $regPath -Name "IconSize" -Value $value
    }
}

function Set-TaskbarSize {
    param($value, $hive = "HKCU")
    $regPath = "Registry::$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    $existing = Get-ItemProperty -Path $regPath -Name "TaskbarSi" -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-ItemProperty -Path $regPath -Name "TaskbarSi" -Value $value -PropertyType DWord -Force | Out-Null
    } else {
        Set-ItemProperty -Path $regPath -Name "TaskbarSi" -Value $value
    }
}

function Restart-Explorer {
    Stop-Process -Name explorer -Force
    Start-Process explorer
}

# GUI
$form = New-Object Windows.Forms.Form
$form.Text = "Icon Size Utility"
$form.Width = 400
$form.Height = 330
$form.StartPosition = "CenterScreen"

# === Desktop group ===
$desktopGroupBox = New-Object Windows.Forms.GroupBox
$desktopGroupBox.Text = "Desktop Icon Size"
$desktopGroupBox.Width = 340
$desktopGroupBox.Height = 80
$desktopGroupBox.Left = 20
$desktopGroupBox.Top = 10

$desktopButtons = @{}
$topOffset = 20
foreach ($label in "Small","Medium","Large","ExtraLarge") {
    $rb = New-Object Windows.Forms.RadioButton
    $rb.Text = $label
    $rb.Left = 15 + (($desktopButtons.Count % 2) * 160)
    $rb.Top = $topOffset + [math]::Floor($desktopButtons.Count / 2) * 25
    $desktopButtons[$label] = $rb
    $desktopGroupBox.Controls.Add($rb)
}
$form.Controls.Add($desktopGroupBox)

# === Taskbar group ===
$taskbarGroupBox = New-Object Windows.Forms.GroupBox
$taskbarGroupBox.Text = "Taskbar Icon Size"
$taskbarGroupBox.Width = 340
$taskbarGroupBox.Height = 80
$taskbarGroupBox.Left = 20
$taskbarGroupBox.Top = 100

$taskbarButtons = @{}
$left = 15
foreach ($label in "Small","Medium","Large") {
    $rb = New-Object Windows.Forms.RadioButton
    $rb.Text = $label
    $rb.Left = $left
    $rb.Top = 30
    $left += 100
    $taskbarButtons[$label] = $rb
    $taskbarGroupBox.Controls.Add($rb)
}
$form.Controls.Add($taskbarGroupBox)

# === Warning label ===
$taskbarWarning = New-Object Windows.Forms.Label
$taskbarWarning.Text = "Warning:  Taskbar size setting may not be supported on `nthis version of Windows."
$taskbarWarning.AutoSize = $true
$taskbarWarning.ForeColor = "DarkRed"
$taskbarWarning.Top = 185
$taskbarWarning.Left = 20
$taskbarWarning.Visible = $false
$form.Controls.Add($taskbarWarning)

# === Buttons ===
$applyBtn = New-Object Windows.Forms.Button
$applyBtn.Text = "Apply"
$applyBtn.Width = 130
$applyBtn.Top = 220
$applyBtn.Left = 40

$applyAllBtn = New-Object Windows.Forms.Button
$applyAllBtn.Text = "Apply to All Users"
$applyAllBtn.Width = 130
$applyAllBtn.Top = 220
$applyAllBtn.Left = 200

$form.Controls.Add($applyBtn)
$form.Controls.Add($applyAllBtn)

# === Preselect current settings ===
$desktopCurrent = Get-CurrentDesktopSize
$taskbarCurrent = Get-CurrentTaskbarSize
if ($desktopButtons.ContainsKey($desktopCurrent)) { $desktopButtons[$desktopCurrent].Checked = $true }
if ($taskbarButtons.ContainsKey($taskbarCurrent)) { $taskbarButtons[$taskbarCurrent].Checked = $true }
if (IsTaskbarSizeUnsupported) { $taskbarWarning.Visible = $true }

# === Apply logic ===
function Apply-Settings {
    param ($allUsers)

    $selectedDesktop = ($desktopButtons.GetEnumerator() | Where-Object { $_.Value.Checked }).Key
    $selectedTaskbar = ($taskbarButtons.GetEnumerator() | Where-Object { $_.Value.Checked }).Key

    if (-not $selectedDesktop -and -not $selectedTaskbar) {
        [System.Windows.Forms.MessageBox]::Show("Please select icon sizes to apply.")
        return
    }

    if ($allUsers -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show("Please run PowerShell as administrator to apply settings to all users.")
        return
    }

    try {
        if ($allUsers) {
            $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
                Where-Object { (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*" }

            foreach ($profile in $profiles) {
                $sid = $profile.PSChildName
                $hive = "HKEY_USERS\$sid"
                if ($selectedDesktop) { Set-DesktopIconSize -value $desktopSizes[$selectedDesktop] -hive $hive }
                if ($selectedTaskbar) { Set-TaskbarSize -value $taskbarSizes[$selectedTaskbar] -hive $hive }
            }
        } else {
            if ($selectedDesktop) { Set-DesktopIconSize -value $desktopSizes[$selectedDesktop] }
            if ($selectedTaskbar) { Set-TaskbarSize -value $taskbarSizes[$selectedTaskbar] }
        }

        Restart-Explorer
        [System.Windows.Forms.MessageBox]::Show("Settings applied successfully.")

    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error applying settings: $_")
    }
}

$applyBtn.Add_Click({ Apply-Settings -allUsers:$false })
$applyAllBtn.Add_Click({ Apply-Settings -allUsers:$true })

# Run GUI
[void]$form.ShowDialog()
