
# This file contains PowerShell snippets that demonstrate how use the
# template engine implemented in ExpandTemplate.ps1 in order to generate
# Registry script files.
# The generated Registry script files cause creation of Windows Explorer's
# context menu item, usually titled "Open with VS Code", which on selection
# opens the respective file or directory in Visual Studio Code.
# Execute the snippets in PowerShell in the directory where this file is 
# located.

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

# Generate AddCode_Example.reg.tmpl from AddCode_Example_Generated.reg.
# Title is parameterized via Title variable via {{ var.Title | regq }} and 
# must be provided via arguments. Other values to be expanded are provided 
# via environment variables: {{ env.USERPROFILE | pathappend:... | regq }}.
# Various forms of spaces and newline within template markup are tested.
./ExpandTemplate.ps1 -Template ./AddCode_Example1.reg.tmpl  `
  -Output ./AddCode_Example_Generated1.reg  `
  -Var 'Title=Open with VS Code'




