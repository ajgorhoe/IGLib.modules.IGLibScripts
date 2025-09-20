# tests/ExpandTemplate.Tests.ps1

# Resolve the folder the test file is in
$here = Split-Path -Parent $PSCommandPath

# ExpandTemplate.ps1 sits in the parent directory 
$sutPath = Join-Path $here '../ExpandTemplate.ps1'

if (-not (Test-Path -LiteralPath $sutPath)) {
  throw "Cannot find ExpandTemplate.ps1 at: $sutPath"
}

# Dot-source the script so its functions are available in this scope
. $sutPath

Describe 'ExpandTemplate streaming expansion' {
  BeforeAll {
    $vars = @{ MyVarSimple = 'NorthEast' }
    $env:ENVSIMPLE = 'abc'
  }

  It 'expands simple var and filters' {
    $tpl = @"
var: {{ var.MyVarSimple }}
lower: {{ var.MyVarSimple | lower }}
upper: {{ var.MyVarSimple | upper }}
"@
    $out = Expand-PlaceholdersStreaming -Text $tpl -Variables $vars
    $out | Should -Match 'var:\s+NorthEast'
    $out | Should -Match 'lower:\s+northeast'
    $out | Should -Match 'upper:\s+NORTHEAST'
  }

  It 'keeps escaped braces literal' {
    $tpl = '\{{ not a placeholder \}} and {{ env.ENVSIMPLE }}'
    $out = Expand-PlaceholdersStreaming -Text $tpl -Variables @{}
    $out | Should -Match '\{\{ not a placeholder \}\}'
    $out | Should -Match 'abc'
  }

  It 'does not emit empty {{}} for real placeholders' {
    $tpl = 'X {{ var.MyVarSimple }} Y'
    $out = Expand-PlaceholdersStreaming -Text $tpl -Variables $vars
    $out | Should -Not -Match '\{\{\}\}'
  }
}
