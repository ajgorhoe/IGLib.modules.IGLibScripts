# tests/ExpandTemplate.Tests.ps1

Describe 'ExpandTemplate streaming expansion (integration)' {

  BeforeAll {
    $script:TestRoot = $PSScriptRoot
    if (-not $script:TestRoot) { $script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $script:SutPath = [System.IO.Path]::GetFullPath( (Join-Path $script:TestRoot '..\ExpandTemplate.ps1') )

    Write-Host "[BeforeAll] TestRoot : $script:TestRoot"
    Write-Host "[BeforeAll] SutPath  : $script:SutPath"
    Write-Host "[BeforeAll] SutPath type: $([string]$script:SutPath).GetType().FullName"

    if (-not (Test-Path -LiteralPath $script:SutPath)) {
      throw "Cannot find ExpandTemplate.ps1 at: $script:SutPath"
    }
    $gi = Get-Item -LiteralPath $script:SutPath -ErrorAction Stop
    Write-Host "[BeforeAll] Get-Item  : $($gi.FullName) (type=$($gi.GetType().FullName))"
  }

  It 'expands simple var and filters' {
    $tpl = @"
var: {{ var.MyVarSimple }}
lower: {{ var.MyVarSimple | lower }}
upper: {{ var.MyVarSimple | upper }}
"@
    $tmpTpl = Join-Path $env:TEMP ("tmpl_{0}.tmpl" -f [guid]::NewGuid())
    $tmpOut = Join-Path $env:TEMP ("out_{0}.txt"  -f [guid]::NewGuid())
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    & ([string]$script:SutPath) `
      -Template $tmpTpl -Output $tmpOut `
      -Var "MyVarSimple=NorthEast" `
      -OutVerbose:$false -OutDebug:$false -OutTrace:$false | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Match 'var:\s+NorthEast'
    $out | Should -Match 'lower:\s+northeast'
    $out | Should -Match 'upper:\s+NORTHEAST'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'keeps escaped braces literal and expands env var' {
    $tpl = '\{{ not a placeholder \}} and {{ env.ENVSIMPLE }}'
    $tmpTpl = Join-Path $env:TEMP ("tmpl_{0}.tmpl" -f [guid]::NewGuid())
    $tmpOut = Join-Path $env:TEMP ("out_{0}.txt"  -f [guid]::NewGuid())
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    $env:ENVSIMPLE = 'abc'

    & ([string]$script:SutPath) `
      -Template $tmpTpl -Output $tmpOut `
      -Var @() `
      -OutVerbose:$false -OutDebug:$false -OutTrace:$false | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Match '\{\{ not a placeholder \}\}'
    $out | Should -Match 'abc'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'does not emit empty {{}} for real placeholders' {
    $tpl = 'X {{ var.MyVarSimple }} Y'
    $tmpTpl = Join-Path $env:TEMP ("tmpl_{0}.tmpl" -f [guid]::NewGuid())
    $tmpOut = Join-Path $env:TEMP ("out_{0}.txt"  -f [guid]::NewGuid())
    Set-Content -LiteralPath $tmpTpl -Value $tpl -Encoding UTF8

    & ([string]$script:SutPath) `
      -Template $tmpTpl -Output $tmpOut `
      -Var "MyVarSimple=NorthEast" `
      -OutVerbose:$false -OutDebug:$false -OutTrace:$false | Out-Null

    $out = Get-Content -LiteralPath $tmpOut -Raw
    $out | Should -Not -Match '\{\{\}\}'
    $out | Should -Match 'X\s+NorthEast\s+Y'

    Remove-Item $tmpTpl,$tmpOut -Force -ErrorAction SilentlyContinue
  }
}
