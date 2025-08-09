# --- Verify "Open with VS Code" context menu entries ---

$Title   = 'Open with VS Code'
# Generate the same KeyName the helper script uses (sanitize Title)
$KeyName = [regex]::Replace($Title, '[^A-Za-z0-9_-]+', '_')
if ([string]::IsNullOrWhiteSpace($KeyName)) { $KeyName = 'CustomMenuItem' }

$roots   = @("HKCU:\Software\Classes","HKLM:\Software\Classes")
$targets = @(
    @{ Name = "Files";       Path = "*\shell" },
    @{ Name = "Directories"; Path = "Directory\shell" },
    @{ Name = "Background";  Path = "Directory\Background\shell" }
)

function Get-DefaultValue([string]$regPath) {
    try { (Get-Item -Path $regPath).GetValue('') } catch { $null }
}

foreach ($root in $roots) {
    foreach ($t in $targets) {
        $itemKey    = Join-Path -Path (Join-Path $root $t.Path) -ChildPath $KeyName
        $commandKey = Join-Path -Path $itemKey -ChildPath 'command'

        if (Test-Path $itemKey) {
            $muiVerb = (Get-ItemProperty -Path $itemKey -ErrorAction SilentlyContinue).MUIVerb
            $icon    = (Get-ItemProperty -Path $itemKey -ErrorAction SilentlyContinue).Icon
            $cmd     = if (Test-Path $commandKey) { Get-DefaultValue $commandKey } else { $null }

            Write-Host "FOUND ($($t.Name)) at: $itemKey" -ForegroundColor Green
            Write-Host "  Title  : $muiVerb"
            if ($icon) { Write-Host "  Icon   : $icon" }
            if ($cmd)  { Write-Host "  Command: $cmd" }
        } else {
            Write-Host "Missing ($($t.Name)) at: $itemKey" -ForegroundColor DarkYellow
        }
    }
}
