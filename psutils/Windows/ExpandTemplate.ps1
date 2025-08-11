param(
    [Parameter(Mandatory)] [string] $Template,
    [string] $Output,
    [hashtable] $Variables,
    [string[]] $Var,
    [string] $VarsFile,
    [switch] $Strict  # fail if any placeholder cannot be resolved
)

# -------- Helpers ----------------------------------------------------------

function Resolve-PathSmart {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return (Resolve-Path -LiteralPath $Path).Path }
    $candidates = @(
        (Join-Path $PSScriptRoot $Path),
        (Join-Path (Get-Location) $Path)
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path } }
    throw "Template/output path not found: $Path"
}


function Get-InitialValue {
    param([hashtable]$Vars, [string]$Ns, [string]$Name, [switch]$Strict)

    switch ($Ns) {
        'var' {
            if (-not $Vars.ContainsKey($Name)) {
                $msg = "Undefined user variable '$Name' ({{ var.$Name }})."
                if ($Strict) { throw $msg } else { throw $msg } # enforce error as requested
            }
            return [string]$Vars[$Name]
        }
        'env' {
            $val = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'User') }
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'Machine') }
            if (-not $val) {
                $msg = "Environment variable '$Name' not defined ({{ env.$Name }})."
                if ($Strict) { throw $msg } else { throw $msg }
            }
            return [string]$val
        }
    }
}

# -------- Load inputs ------------------------------------------------------

$tplPath = Resolve-PathSmart $Template
$tplText = Get-Content -LiteralPath $tplPath -Raw

# Compose variables with precedence
$varsFromFile = Load-VarsFile $VarsFile
$varsMerged   = Merge-Variables $varsFromFile $Variables
$varsCli      = Parse-VarPairs $Var
$VARS         = Merge-Variables $varsMerged $varsCli

# Compute default output if omitted
if (-not $Output) {
    $dir = [System.IO.Path]::GetDirectoryName($tplPath)
    $fn  = [System.IO.Path]::GetFileName($tplPath)
    $base = $fn
    foreach ($suffix in @('.tmpl','.template','.tpl','.in')) {
        if ($base.ToLower().EndsWith($suffix)) {
            $base = $base.Substring(0, $base.Length - $suffix.Length)
            break
        }
    }
    if ($base -eq $fn) { $base = $fn + '.out' }
    $Output = Join-Path $dir $base
} else {
    $Output = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $PSScriptRoot $Output }
}

# -------- Expand template --------------------------------------------------

$pattern = '\{\{\s*(.+?)\s*\}\}'
$errors  = New-Object System.Collections.Generic.List[string]

$expanded = [System.Text.RegularExpressions.Regex]::Replace(
    $tplText,
    $pattern,
    {
        param($m)
        $expr = $m.Groups[1].Value
        try {
            $ph   = Parse-Placeholder $expr
            $val0 = Get-InitialValue -Vars $VARS -Ns $ph.ns -Name $ph.name -Strict:$Strict
            $out  = Apply-Filters -Value $val0 -Pipeline $ph.filters
            return $out
        } catch {
            $errors.Add("Error in placeholder '{{ $expr }}': $($_.Exception.Message)")
            return "<ERROR:$expr>"
        }
    }
)

if ($errors.Count -gt 0) {
    $nl = [Environment]::NewLine
    Write-Error ("Template expansion failed:{0}{1}" -f $nl, ($errors -join $nl))
    exit 1
}

# Write as UTF-16LE (what regedit expects for Unicode .reg files)
Set-Content -LiteralPath $Output -Value $expanded -Encoding Unicode
Write-Host "Template expanded to: $Output"
