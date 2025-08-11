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
    throw "Template/output path not found: ${Path}"
}

function ConvertTo-Hashtable {
    param($Object)
    if ($Object -is [hashtable]) { return $Object }
    if ($null -eq $Object) { return @{} }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        $arr = @()
        foreach ($item in $Object) { $arr += (ConvertTo-Hashtable $item) }
        return $arr
    }
    if ($Object.PSObject -and $Object.PSObject.Properties) {
        $ht = @{}
        foreach ($p in $Object.PSObject.Properties) {
            $ht[$p.Name] = ConvertTo-Hashtable $p.Value
        }
        return $ht
    }
    return $Object
}

function Load-VarsFile {
    param([string]$Path)
    if (-not $Path) { return @{} }
    $full = Resolve-PathSmart $Path
    $ext  = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    switch ($ext) {
        '.json' {
            try {
                $raw = Get-Content -LiteralPath $full -Raw
                $obj = $raw | ConvertFrom-Json
                return ConvertTo-Hashtable $obj
            } catch { throw "Failed to parse JSON vars file '${full}': $($_.Exception.Message)" }
        }
        '.psd1' {
            try { return Import-PowerShellDataFile -LiteralPath $full }
            catch { throw "Failed to parse PSD1 vars file '${full}': $($_.Exception.Message)" }
        }
        default { throw "Unsupported vars file extension '${ext}'. Use .json or .psd1." }
    }
}

function Merge-Variables {
    param([hashtable]$Base, [hashtable]$Overlay)
    $dest = @{}
    if ($Base)    { foreach ($k in $Base.Keys)    { $dest[$k] = $Base[$k] } }
    if ($Overlay) { foreach ($k in $Overlay.Keys) { $dest[$k] = $Overlay[$k] } }
    return $dest
}

function Parse-VarPairs {
    param([string[]]$Pairs)
    $ht = @{}
    foreach ($p in ($Pairs | Where-Object { $_ -ne $null })) {
        if ($p -notmatch '^\s*([^=]+)\s*=\s*(.*)\s*$') { throw "Invalid -Var entry '${p}'. Use Name=Value." }
        $name = $Matches[1].Trim()
        $val  = $Matches[2]
        $ht[$name] = $val
    }
    return $ht
}

function Apply-Filters {
    param(
        [string] $Value,
        [object[]] $Pipeline  # @(@{name='filter'; arg='...'}, ...)
    )

    foreach ($f in $Pipeline) {
        $name = $f.name.ToLowerInvariant()
        $arg  = $f.arg

        switch ($name) {
            'trim'       { $Value = $Value.Trim() }
            'upper'      { $Value = $Value.ToUpper() }
            'lower'      { $Value = $Value.ToLower() }
            'regq'       { $Value = $Value -replace '"', '\"' }
            'quote'      { $Value = '"' + $Value + '"' }
            'append'     { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'pathappend' { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) } # verbatim append
            'addarg'     { $Value = $Value + ' "' + ($(if ($null -ne $arg) { $arg } else { '' })) + '"' }

            'expandsz' {
                # Encode $Value as REG_EXPAND_SZ (UTF-16LE with terminating null), return "hex(2):aa,bb,..."
                $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value + [char]0)
                $hex   = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ','
                $Value = 'hex(2):' + $hex
            }

            default { throw "Unknown filter '${name}'." }
        }
    }
    return $Value
}

function Parse-Placeholder {
    param([string]$ExprText)
    # Expected:  var.NAME | filter[: "arg"] | ...
    #         or env.NAME | ...
    $parts = $ExprText -split '\|'
    if ($parts.Count -lt 1) { throw "Empty expression in placeholder." }

    $head = $parts[0].Trim()
    if ($head -notmatch '^(?<ns>var|env)\.(?<name>[A-Za-z_][A-Za-z0-9_\.]*)$') {
        throw "Invalid placeholder head '${head}'. Use 'var.Name' or 'env.NAME'."
    }
    $ns   = $Matches['ns']
    $name = $Matches['name']

    # parse filter segments
    $filters = @()
    for ($i=1; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i].Trim()
        if (-not $seg) { continue }

        $fname = $seg
        $farg  = $null

        # filter:"arg"  (arg may contain \" escapes)
        if ($seg -match '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*"(?<arg>(?:[^"\\]|\\.)*)"\s*$') {
            $fname = $Matches['fn']
            $farg  = $Matches['arg'] -replace '\\\"','"'
        } elseif ($seg -match '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)\s*$') {
            $fname = $Matches['fn']
            $farg  = $null
        } else {
            throw "Invalid filter segment '${seg}'. Use filter or filter:""arg""."
        }
        $filters += @{ name = $fname; arg = $farg }
    }

    return @{ ns = $ns; name = $name; filters = $filters }
}

function Get-InitialValue {
    param([hashtable]$Vars, [string]$Ns, [string]$Name, [switch]$Strict)

    switch ($Ns) {
        'var' {
            if (-not $Vars.ContainsKey($Name)) {
                $msg = "Undefined user variable '${Name}' ({{ var.${Name} }})."
                throw $msg
            }
            return [string]$Vars[$Name]
        }
        'env' {
            $val = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'User') }
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'Machine') }
            if (-not $val) {
                $msg = "Environment variable '${Name}' not defined ({{ env.${Name} }})."
                throw $msg
            }
            return [string]$val
        }
    }
}

# -------- Load inputs ------------------------------------------------------

$tplPath = Resolve-PathSmart $Template
$tplText = Get-Content -LiteralPath $tplPath -Raw

# Compose variables with precedence: VarsFile < Variables < Var
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
    if (-not [System.IO.Path]::IsPathRooted($Output)) {
        $Output = Join-Path $PSScriptRoot $Output
    }
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
            $errors.Add("Error in placeholder '{{ ${expr} }}': $($_.Exception.Message)")
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
Write-Host "Template expanded to: ${Output}"
