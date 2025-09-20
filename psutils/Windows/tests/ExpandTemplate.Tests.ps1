$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..\ExpandTemplate.ps1'

Describe 'ExpandTemplate streaming expansion' {
  BeforeAll {
    . $script
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
