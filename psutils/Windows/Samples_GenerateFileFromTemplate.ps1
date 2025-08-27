
# This file contains PowerShell snippets that demonstrate how to use the
# template engine implemented in ExpandTemplate.ps1 in order to generate
# sample text files from their template files.
# The templates contain various kinds of placeholders (to substitute 
# environment variables or user-provided variables in form of user variables
# (i.e., key-value pairs), with different kinds of filters applied, or without
# filters).

# TemplateExample.txt.tmpl is a template file that contains diverse set of
# placeholders.
# The following environment variables need to be defined for successful
# generation (suggested values are also provided):
#   ENVPATHWIN = C:\Users\Uporabnik\Documents\MyDoc.md
#   ENVPATHUNIX = /home/uporabnik/doc/MyDoc.md
#   ENVSIMPLE = EnvSimpleValue
#   ENVLONGER = "Value of the environment variable (longer)."
# The following user-provided variables need to be defined:
#   MyVarSimple = NorthEast
#   MyVarLong = '  This is a longer "str", \ used to demonstrate composed filters.  '
#   PathWin = C:\Program Files (x86)\Microsoft SQL Server\
#   PathUnix = ~/doc/MyDoc.md
#   DirtyRelativePath = "../.\.\.//../users//\\/aa/./x.xml"
#   DirtyAbsolutePath = "C:\users\\Uporabnik/.//..\Uporabnik/doc/\\/Mydoc.dox"

# Generate TemplateExample_Generated.txt from TemplateExample.txt.tmpl,
# where variables are passed via -Var array parameter:
# Define the necessary environment variables (in typical use, these would
# already be defined in the environment):
$Env:ENVPATHWIN = "C:\Users\Uporabnik\Documents\MyDoc.md"
$Env:ENVPATHUNIX = "/home/uporabnik/doc/MyDoc.md"
$Env:ENVSIMPLE = "EnvSimpleValue"
$Env:ENVLONGER = "Value of the environment variable (longer)."
# Define user-provided variables:
$MyVarSimple = "NorthEast"
$MyVarLong = '  This is a longer "str", \ used to demonstrate composed filters.  '
$PathWin = "C:\Program Files (x86)\Microsoft SQL Server\"
$PathUnix = "~/doc/MyDoc.md"
$DirtyRelativePath = "../.\.\.//../users//\\/aa/./x.xml"
$DirtyAbsolutePath = "C:\users\\Uporabnik/.//..\Uporabnik/doc/\\/Mydoc.dox"
# Run the template engine to generate the output file:
./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
  -Output TemplateExample.txt  `
  -Var @( "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
    "PathWin=$PathWin", "PathUnix=$PathUnix",
    "DirtyRelativePath=$DirtyRelativePath", "DirtyAbsolutePath=$DirtyAbsolutePath" )


