
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
#   EscapedStr = "sq \' dq \`" bsl \\ nl \n cr \r ht \t vt \v bsp \b ff \f null \0 nl \012 A \101 sp \040 ht \x09 Z \x5A ! \x21 weird \x4142 ☺ \u263A ☃ \u2603 π \u03C0 A \u0041 gothicAhsa 𐌰 \U00010330 rocket 🚀 \U0001F680 cat 🐈 \U0001F408"
#   ForUrlEncoding = "Café Münchën!.#.$.&. .'.(.).*.+.,./.:.;.=.?.@.[.]"
#   ForXMLEncoding = "`"Hello & Goodbye!`"  5 < 6 & 7 > 4  <a id=e55>#e55</a>"

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
$EscapedStr = "sq \' dq \`" bsl \\ nl \n cr \r ht \t vt \v bsp \b ff \f null \0 nl \012 ETX \x03 ACK \x06 DEL \x7F A \101 sp \040 ht \x09 Z \x5A ! \x21 weird \x4142 ☺ \u263A ☃ \u2603 π \u03C0 A \u0041 gothicAhsa 𐌰 \U00010330 rocket 🚀 \U0001F680 cat 🐈 \U0001F408"
$EscapedStrSimple = "sq \' dq \`" bsl \\ nl \n cr \r ht \t vt \v bsp \b ff \f null \0 nl \012 A \101 sp \040 ht \x09 Z \x5A ! \x21 weird \x4142 ☺ \u263A ☃ "
$ForUrlEncoding = "Café Münchën!.#.$.&. .'.(.).*.+.,./.:.;.=.?.@.[.]"
$ForXMLEncoding = "`"Hello & Goodbye!`"  5 < 6 & 7 > 4  <a id=e55>#e55</a>"
# Run the template engine to generate the output file:
Measure-Command {
  ./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
    -Output TemplateExample.txt  `
    -Var @( "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
      "PathWin=$PathWin", "PathUnix=$PathUnix",
      "DirtyRelativePath=$DirtyRelativePath", "DirtyAbsolutePath=$DirtyAbsolutePath",
      "EscapedStr=$EscapedStr", "EscapedStrSimple=$EscapedStrSimple", 
      "ForUrlEncoding=$ForUrlEncoding", "ForXMLEncoding=$ForXMLEncoding" )
}

# Just another form of the above, without parentheses for the array parameter:
./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
  -Output TemplateExample.txt  `
  -Var "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
    "PathWin=$PathWin", "PathUnix=$PathUnix",
    "DirtyRelativePath=$DirtyRelativePath", "DirtyAbsolutePath=$DirtyAbsolutePath",
    "EscapedStr=$EscapedStr", "EscapedStrSimple=$EscapedStrSimple", 
    "ForUrlEncoding=$ForUrlEncoding", "ForXMLEncoding=$ForXMLEncoding" 

# TODO: Check why spaces at the beginning of variable values are lost in this mode.
# Jet another form of the above call, using -Variables hashtable parameter:
$VariablesHashTab = @{ MyVarSimple=$MyVarSimple; MyVarLong=$MyVarLong;
    PathWin=$PathWin; PathUnix=$PathUnix;
    DirtyRelativePath=$DirtyRelativePath; DirtyAbsolutePath=$DirtyAbsolutePath;
    EscapedStr=$EscapedStr; EscapedStrSimple=$EscapedStrSimple; 
    ForUrlEncoding=$ForUrlEncoding; ForXMLEncoding=$ForXMLEncoding }
./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
  -Output TemplateExample.txt  `
  -Variables $VariablesHashTab


# Mixed mode, with some variables passed via -Var array parameter, and some
# via -Variables hashtable parameter:
./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
  -Output TemplateExample.txt  `
  -Var @( "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
    "PathWin=$PathWin" )  `
    -Variables @{ PathWin=$PathWin; PathUnix=$PathUnix;
    DirtyRelativePath=$DirtyRelativePath; DirtyAbsolutePath=$DirtyAbsolutePath;
    EscapedStr=$EscapedStr; EscapedStrSimple=$EscapedStrSimple; 
    ForUrlEncoding=$ForUrlEncoding; ForXMLEncoding=$ForXMLEncoding }


# Mixed mode, repeating the -Var:
./ExpandTemplate.ps1 -Template TemplateExample.txt.tmpl  `
  -Output TemplateExample.txt  `
  -Var "MyVarSimple=$MyVarSimple" -Var "MyVarLong=$MyVarLong"  `
  -Var "PathWin=$PathWin"  `
  -Variables @{ PathWin=$PathWin; PathUnix=$PathUnix;
    DirtyRelativePath=$DirtyRelativePath; DirtyAbsolutePath=$DirtyAbsolutePath;
    EscapedStr=$EscapedStr; EscapedStrSimple=$EscapedStrSimple; 
    ForUrlEncoding=$ForUrlEncoding; ForXMLEncoding=$ForXMLEncoding }


    

# Running on the SHORT TEMPLATE FILE (for quick testing):

./ExpandTemplate.ps1 -Template TemplateShort.txt.tmpl  `
  -Output TemplateShort.txt  `
  -Var @( "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
    "PathWin=$PathWin", "PathUnix=$PathUnix",
    "DirtyRelativePath=$DirtyRelativePath", "DirtyAbsolutePath=$DirtyAbsolutePath",
    "EscapedStr=$EscapedStr", "EscapedStrSimple=$EscapedStrSimple", 
    "ForUrlEncoding=$ForUrlEncoding", "ForXMLEncoding=$ForXMLEncoding" )



# TESTS with Pester:

# Before running the tests, ensure that the preconditions are met:
Measure-Command {
  ./tests/LoadPester.ps1
}


# Run all tests in the tests subdirectory:
Invoke-Pester -Path .\tests -Output Detailed

# Run all tests in a single test file:
Invoke-Pester .\tests\ExpandTemplate.Tests.ps1 -Output Detailed

# Run a specific test by its name:
Invoke-Pester -Path .\tests -TestName 'expands simple var and filters'

# Tag the It/Describe blocks, then run by tag:
Invoke-Pester -Path .\tests -Tag 'streaming'

# For CI (sets exit code on failure):
Invoke-Pester -Path .\tests -CI -EnableExit




