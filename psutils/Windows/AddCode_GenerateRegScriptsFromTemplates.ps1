
# This file contains PowerShell snippets that demonstrate how use the
# template engine implemented in ExpandTemplate.ps1 in order to generate
# Registry script files.
# The generated Registry script files cause creation of Windows Explorer's
# context menu item, usually titled "Open with VS Code", which on selection
# opens the respective file or directory in Visual Studio Code.
# Execute the snippets in PowerShell in the directory where this file is 
# located.

# AddCode_Example_WithPlaceholders.reg has simple placeholders only for user
# name, also expandable by ExpandTemplate.ps1:

# Generate AddCode_Example.reg from AddCode_Example_WithPlaceholders.reg.
# This can simply be done by copying the file and manually replacing the
# placeholders {{env:USERNAME}} with the current user's login name.
# These placeholders also represent the markup for replacement of the
# current user's login name by the template engine, and we can use the
# ExpandTemplate.ps1 to do the job:
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example_WithPlaceholders.reg `
  -Output   .\AddCode_Example_Generated.reg `
  -Variables @{ Title = 'Open with VS Code' }

# AddCode_Example1.reg.tmpl uses a single variable substitute (Title) and one
# environment variable substitute (USERPROFILE). The placeholders are written
# in different ways, including additional spaces and newlines, to test the
# template engine's ability to handle them.

# Generate AddCode_Example_Generated1.reg from AddCode_Example1.reg.tmpl.
# Title is parameterized via Title variable via {{ var.Title | regq }} and 
# must be provided via arguments. Other values to be expanded are provided 
# via environment variables: {{ env.USERPROFILE | pathappend:... | regq }}.
# Various forms of spaces and newline within template markup are tested:
./ExpandTemplate.ps1 -Template ./AddCode_Example1.reg.tmpl  `
  -Output ./AddCode_Example_Generated1.reg  `
  -Var 'Title=Open with VS Code'


# AddCode_Example1.reg.tmpl uses several variable substitutes (Title, 
# MyUserName, VsCodeLocation) and environment variable substitute (USERNAME,
# LOCALAPPDATA). It is used to demonstrate that passing several variables
# to the template engine works as expected.

# Generate AddCode_Example_Generated2.reg from AddCode_Example2.reg.tmpl.
# Variables are passed via -Var array parameter, and environment variables
# are used in the template markup:
$MyUserName = $env:USERNAME
$VsCodeLocation = $env:LOCALAPPDATA + '\Programs\Microsoft VS Code\'
./ExpandTemplate.ps1 -Template AddCode_Example2.reg.tmpl  `
  -Output AddCode_Example_Generated2.reg  `
  -Var "MyUserName=$MyUserName", "VsCodeLocation=$VsCodeLocation", 
    'Title=Open with VS Code'

# The same as above, except the array parameter -Var is specified with 
# parentheses:
$MyUserName = $env:USERNAME
$VsCodeLocation = $env:LOCALAPPDATA + '\Programs\Microsoft VS Code\'
./ExpandTemplate.ps1 -Template AddCode_Example2.reg.tmpl  `
  -Output AddCode_Example_Generated2.reg  `
  -Var @( "MyUserName=$MyUserName", "VsCodeLocation=$VsCodeLocation", 
    'Title=Open with VS Code' )

  
# Generate AddCode_Example_Generated2.reg from AddCode_Example2.reg.tmpl.
# Similar as above, except variables are passed via -Variables hashtable
# parameter:
$MyUserName = $env:USERNAME
$VsCodeLocation = $env:LOCALAPPDATA + '\Programs\Microsoft VS Code\'
./ExpandTemplate.ps1 -Template AddCode_Example2.reg.tmpl  `
  -Output AddCode_Example_Generated2.reg  `
  -Variables @{ MyUserName=$MyUserName ; 
    VsCodeLocation=$VsCodeLocation ; Title='Open with VS Code' }


