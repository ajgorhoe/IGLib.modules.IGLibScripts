# Verify entries for "Open with VS Code"
$Title   = 'Open with VS Code'
$KeyName = [regex]::Replace($Title, '[^A-Za-z0-9_-]+', '_'); if ([string]::IsNullOrWhiteSpace($KeyName)) { $KeyName = 'CustomMenuItem' }

$roots = @("HKCU:\Software\Classes","HKLM:\Software\Classes")

$targets = @(
    @{ Name='Files';       Item="*\shell\$KeyName";             Command="*\shell\$KeyName\command" },
    @{ Name='Directories'; Item="Directory\shell\$KeyName";     Command="Directory\shell\$KeyName\command" },
    @{ Name='Background';  Item="Directory\Background\shell\$KeyName"; Command="Directory\Background\shell\$KeyName\command" }
)

foreach ($root in $roots) {
    foreach ($t in $targets) {
        $itemKey    = "$root\" + $t.Item
        $commandKey = "$root\" + $t.Command

        if (Test-Path -LiteralPath $itemKey) {
            $muiVerb = (Get-ItemProperty -LiteralPath $itemKey -ErrorAction SilentlyContinue).MUIVerb
            $icon    = (Get-ItemProperty -LiteralPath $itemKey -ErrorAction SilentlyContinue).Icon
            $cmd     = $null
            if (Test-Path -LiteralPath $commandKey) {
                $cmd = (Get-Item -LiteralPath $commandKey).GetValue('')
            }

            Write-Host "FOUND ($($t.Name)) at: $itemKey" -ForegroundColor Green
            Write-Host "  Title  : $muiVerb"
            if ($icon) { Write-Host "  Icon   : $icon" }
            if ($cmd)  { Write-Host "  Command: $cmd" }
        } else {
            Write-Host "Missing ($($t.Name)) at: $itemKey" -ForegroundColor DarkYellow
        }
    }
}
