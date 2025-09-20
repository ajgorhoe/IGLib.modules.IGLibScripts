# tests/ExpandTemplate.Tests.ps1

# --- Reliable path resolution (works under Pester v5 on PS 5.1/7+) ---
$here    = $PSScriptRoot  # folder containing THIS test file
$sutPath = [System.IO.Path]::GetFullPath( (Join-Path $here '..\ExpandTemplate.ps1') )

if (-not (Test-Path -LiteralPath $sutPath)) {
  throw "Cannot find ExpandTemplate.ps1 at: $sutPath"
}

Describe 'ExpandTemplate streaming expansion (integration)' {

  It 'expands simple var and filters' {
    $tpl = @"
var: {{ var.MyVarSimple }}
lower: {{ var.MyVarSimple | lower }}
upper: {{ var.MyVarSimple | upper }}
"@

    $tmpTpl = Join-Path $env:TEMP "tmpl_$([guid]::NewGuid()).tmpl"
    $tmpOut = Join-Path $env:TEMP "out_$([guid]::NewGuid()).txt"
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    & $sutPath -Template $tmpTpl -Output $tmpOut -Variables @{ MyVarSimple = 'NorthEast' } | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Match 'var:\s+NorthEast'
    $out | Should -Match 'lower:\s+northeast'
    $out | Should -Match 'upper:\s+NORTHEAST'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'keeps escaped braces literal and expands env var' {
    $tpl = '\{{ not a placeholder \}} and {{ env.ENVSIMPLE }}'
    $tmpTpl = Join-Path $env:TEMP "tmpl_$([guid]::NewGuid()).tmpl"
    $tmpOut = Join-Path $env:TEMP "out_$([guid]::NewGuid()).txt"
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    $env:ENVSIMPLE = 'abc'
    & $sutPath -Template $tmpTpl -Output $tmpOut -Variables @{} | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Match '\{\{ not a placeholder \}\}'
    $out | Should -Match 'abc'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'does not emit empty {{}} for real placeholders' {
    $tpl = 'X {{ var.MyVarSimple }} Y'
    $tmpTpl = Join-Path $env:TEMP "tmpl_$([guid]::NewGuid()).tmpl"
    $tmpOut = Join-Path $env:TEMP "out_$([guid]::NewGuid()).txt"
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    & $sutPath -Template $tmpTpl -Output $tmpOut -Variables @{ MyVarSimple = 'NorthEast' } | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Not -Match '\{\{\}\}'
    $out | Should -Match 'X\s+NorthEast\s+Y'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }
}
