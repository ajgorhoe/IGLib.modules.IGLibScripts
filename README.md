# About this Repository

Copyright (c) Igor Grešovnik

This repository is part of the Investigative Generic Library (*IGLib*). It contains some utility scripts that are used in IGLib and wider - batch, PowerShell, and C# scripts.

Main branch of the IGLibScript repository: *main*

Main branch of the IGLibScriptPS repository: *mainPS*

See [LICENSE.md](./LICENSE.md) for terms of use.

## Documentation for Part of Batch Scripts

> **ToDo**: Clean this section.

This section contains documentation for some of the scripts. For more extensive documentation, refer documentation comments in scripts themselves. This section replaces [IGLibScripts_old.html](./IGLibScripts_old.html)

*Contents**:  

* [Introduction](#introduction)
* [Selected Utilities](#selected-utilities)
  * [UpdateRepo.bat](#updaterepobat)
  * [PrintRepoSettings.bat](#printreposettingsbat)
  * [SetVar.bat](#setvarbat)
  * [RunLocal.bat](#runlocalbat)
  * [SetScriptReferences.bat](#setscriptreferencesbat)
  * [PrintScriptReferences.bat](#printscriptreferencesbat)  

## Introduction

The IHLibScripts is an ***IGLib*** (**Investigation Generic Library**) module that contains some useful batch scripts and shell scripts used by the library (e.g. for managing repository cloning and updates).
Mainly these utilities are generally useful and their use is not limited to IGLib.

## Selected Utilities

### UpdateRepo.bat

Clones or updates a Git repository at particular location on the disk. Parameters of the operation are obtained from environment variables with a predefined meaning for this command. These variables are:  

> **_ModuleDir_** - a directory into which the repository is cloned.  
> **_CheckoutBranch_** - branch that is checked out / switched to by the command.  
> **_RepositoryAddress_** - address of remote Git repository that is cloned into the _ModuleDir_ or from which repository is updated (changes pulled).  
> **_Remote_** (optional, default is _origin_) - name of the main Git remote, corresponding to _RepositoryAddress_. All remote operations executed by this script will act on remote with this name.  
> **_RepositoryAddressSecondary_** (optional, default is undefined) - address of alternative remote repository. In case the script performs cloning of the repository (which is when the repository has not yet been cloned at the location specified by _ModuleDir_, or when that directory does not contain a valid Git repository), the secondary remote specified by _RemoteSecondary_ will be defined on the cloned repository and linked tho this address.  
> **_RemoteSecondary_** (optional, default is _originsecondary_) - name of the secondary remote. If the script performs cloning of the repository at _RepositoryAddress_ then  it will assign the address _RepositoryAddressSecondary_ to a remote named _RemoteSecondary_.  
> _**RepositoryAddressLocal**_ (optinal, default is undefined) - an eventual additional alternative repository address, usually a local repository but not necessarily. Behavior is equivalent as for _RepositoryAddressSecondary_ / _RemoteSecondary_: If the variable is defined and not an empty string, and the script also performs cloning (i.t., the repository is first cloned at the location _ModuleDir_), then the script also defines the remote named _RemoteLocal_ with this address.  
> _**RemoteLocal**_ (optional, default is _local_) - name of the additional alternative origin whose address is set to the value of _RepositoryAddressLocal_ if this variable is defined.

**Usage**:  

> _UpdateRepo.bat_  
> 
> > Clones or updates the repository whose address, local checkout path, and other parameters are defined by the agreed environment variables mentioned above.  
> > In order for this to work, environment variables that defines **parameters** of operation (repository cloning or updating) **must be set prior to calling the script** _UpdateRepo.bat_, and this is most often done by packing these definitions into a separate _settings script_ and _calling_ the script before calling _UpdateRepo.bat_.  
> > The disadvantage of this approach is that the _settings script_ will have side effects (environment variables set) in the context where _UpdateRepo.bat_ is called, so whenever we want to call the script in this way, we must pollute the environment by setting the environment variables that carry operation parameters for the script. This can be avoided by calling the script in the second way, with _settings script_ and its eventual arguments _specified as argumens to the_ _UpdateRepo call_ (see the description below). In this way, the _settings_ _script_ will is called recursively within the body of _UpdateRepo.bat_, enclosed in _setlocal / endlocal_ block, which prevents propagation of side effects the caller's context.  

> _UpdateRepo.bat EmbeddedCommand <arg 1 arg 2 ....>_  
> 
> > This will first call the _EmbeddedCommand_ with eventual arguments (optional parameters _arg1_, _arg2_, etc.), and then perform the repository update in the same manner as _UpdateRepo_ called without arguments.  
> > The _EmbeddedCommand_ will typically be another batch _script that sets all the relevant environment variables_ that define parameters for repository updating or cloning (see description of parameters via environment variables above).  
> > The body of the _UpdateRepo.bat_  script is **embedded in setlocal / endlocal** block, therefore any **side effects will not propagate to the caller environment**. This applies for side effects of _UpdateRepo.bat_ as well as _EmbeddedCommand_.  
> > It is desirable that **_update setting scripts_** (that set environment variables carrying parameters for repository updating operations), which are commonly specified as the _EmbeddedCommand_ argument, are also defined in the way that they can take embedded command to be run (together with its arguments) specified via command-line arguments of the settings script. In this way, one can chain nested calls of useful commands or scripts that are called recursively before the main body of the _UpdateRepo_ script is executed. This adds a great flexibility to the repository updating scripts while preventing the scripts from polluting the calling environment with environment variables that are necessary to carry update parameters to scripts. A typical use of this is passing to the _UpdateRepo_ script a settings script, e.g. _SettingsIGLibScripts.bat,_ which defines the necessary environment variables containing updating parameters such as local directory and remote address (in this example, for cloning / updating the IGLibScripts repository to a specified location by the specified remote repository). Then, with additional arguments, further commands can be passed to the _SettingsIGLibScripts_ script, which would be executed recursively within _SettingsIGLibScripts.bat_, after the script main body that sets the environment variables. These further commands can for example modify some values set by the script, which enables **reusing the settings script**, but **with some updating parameters modified** (for example **_ModuleDir_** or **_RepositoryAddressSecondary_**) to achieve a bit different behavior. This can be achieved e.g. by the _**SetVar.bat**_ script (see its description), which sets the specified environment variable. The (imaginary, assuming existence of the  setting _SettingsIGLibScripts.bat_ script) example command below would call the _UpdateRepo_ script to update (or clone) the repository defined by parameters set by the _SettingsIGLibScripts_ script, but overriding the values of the **_ModuleDir_** (defining the repository's local cloning directory) and the **_CheckoutBranch_** (defining the branch that is checked out by the _UpdateRepo_ script):  
> > 
> > > _<u>UpdateRepo</u> "___D:\\GitUser_\\RepositorySettings\\SettingsIGLibScripts.bat"  <u>SetVar</u> ModuleDir "D:\\GitUser\\My Workspace" <u>SetVar</u> CheckoutBranch "release/1.9.1"  
> > > _
> > 
> > The .bat extensions in some script names were omitted in the above command, and scripts available in the _IGLibScripts_ repository are underlined. To check out how this actually works in practice, refer to examples contained in <_IGLibScripts_\>\\examples\_repos .  

**Operation**:  
If the directory specified by  does **not** contain **a valid Git repository**, the directory is first **removed** (recursively, including complete direcory structure). The script must therefore be used with some caution, please take care that **_ModuleDir_** **does not point to a directory with useful content that is not a clone of the repository specified by _RepositoryAddre__ss_**.  
Then, if the directory specified by **_ModuleDir_** does **not exist**, the **repository at** the address **_RepositoryAddress_** is **cloned into** **_ModuleDir_**. After cloning is complete, the **additional remotes are defined** on the cloned repository, provided that the corresponding addresses, **_RepositoryAddressSecondary_** or / and _**RepositoryAddressLocal**_ are specified. Finally, the remote branch specified by **_CheckoutBranch_** is checked out and updated (pulled) from the main remote from which repository was cloned.  
If the directory specified by **_ModuleDir_** **already contains a Git repository** then the script will only **make sure that the correct branch** (specified by **_CheckoutBranch_**) **is checked out** and will **update the branch** by pulling any changes **from the remote repository** (at **_RepositoryAddress_**).

**Warning**:  
When repository already exists (so it does not need to be cloned), the script will **not verify whether the repository contained in** ****_ModuleDir_** is the correct one and corresponds to the remote repository at** ****_RepositoryAddress_****. Performing  such a check would require execution of additional scripts (such scripts may be provided in the future).

### PrintRepoSettings.bat

Prints out values of the environment variables that are relevant (contain parameter values) for scripts that update or clone repositories.  
**Usage**:  

> _PrintRepoSettings.bat  
> _
> 
> > Just prints out (to the console) values of environment variables that are used to define parameters for repository updates (e.g. by the _UpdateRepo.bat_ script). See description of _UpdateRepo.bat_ for description of the relevant environment variables carrying update parameters.  
> 
> __PrintRepoSettings_.bat EmbeddedCommand <arg 1 arg 2 ....>_  
> 
> > Prints out values of the environment variables relevant for repository updates (in the same way as when calling the script without arguments, such as above), but in addition to that, the script runs the command _EmbeddedCommand_, passing to it all the eventual remaining arguments (the optional arguments _arg1_, _arg2_, etc.).  
> > Typically the _EmbeddedCommand_ will be a script that also sets the environment variables related to repository updating.  
> > The _EmbeddedCommand_ is **run within a setlocal / endlocal block**, therefore **no side effects** will propagate to the calling environment.  

  

### SetVar.bat

Sets the value of the specified environment variable. The script requires at least two arguments, of which the first one is the name of the environment variable and the second one is the value to be assigned to this variable. The value assigned will persist in the calling environment.  
Beside variable name and value, the script can **optionally** take **further arguments**, which in this case define an **embedded command with eventual arguments** executed recursively within the script. The embedded command (when defined) is **executed after the specified variable value is assigned**, and **any side effects of the embedded command are propagated** to the calling environment. This enables recursive chaining with other commands (e.g., as in example with _UpdateRepo.bat_ script mentioned in script description) or setting multiple variables by a single command-line, e.g.:  

> _<u>SetVar</u> CloningDirectory "D:\\My Repositories" <u>SetVar</u> RepoAddress https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git_  

**Usage**:  

> _SetVar.bat VariableName ValueAssigned_  
> 
> > Assigns the value _ValueAssigned_ to environment variable named _VariableName_. In line with Windows script rules, the parameters must be embedded in double quotes if they contain spaces.  
> 
> _SetVar.bat VariableName ValueAssigned_ _EmbeddedCommand <arg 1 arg 2 ....>_

> > The same as above, but in addition the _EmbeddedCommand_ is also executed recursively, receiving the eventual remaining arguments (the optional _arg1_, _arg2_, etc.)  
> > The _EmbeddedCommand_ is **_executed after the variable is assigned_**. In his way, the recursively executed command can already make use of the newly assigned value of the environment variable _VariableName_ that had been assigned by the script.  

  

### RunLocal.bat

Executes the specified command or script in a local context (embedded in the setlocal / endlocal block), such that any changes in definitions or values of environment variables that the command may cause are not propagated to the calling environment.  
For exemple, if you run the following command in the console window:  

> _RunLocal SetVar xy NewValue_  

the _SetVar_ script will set the value of the environment variable named _xy_ but the effect will only be local (limited to the _RunLocal_ script) and the assignment will not persist in the calling environment after the call. This can be verified by running  

> _set xy_  

or  

> _echo %xy%_  

in the same console window after running the above command. On the contrary, when running _SetVar_ script directly, i.e.:  

> _SetVar xy NewValue_

 the variable _xy_ will actually be defined in the calling environment after the call and its value will be _NewValue_, as expected.

At first glance this does not seem like a very useful functionality, however, it may be quite valuable when testing the scripts similar to those contained  in the IGLibScripts repository, or in case of these scripts, also to contain side effects of scripts that do something but also have unintentional side effects.

For example, several scripts described in this document can recursively run embedded commands that can be specified via additional command-line arguments that follow those that are requested (if any). Batch scripts of the Windows command shell are rather limited in how command-line arguments can be processed within scripts (e.g. in the number of arguments that can be referenced by consecutive numbers, like %1, %2, etc., limited to 9; or the ways how arbitrary groups of command-line arguments can be passed on to commands run recursively). In order to evade some of these limitations we needed to define auxiliary variables used to assemble command-lines for recursive commands, and in some scripts this cannot be done within _setlocal_ / _endlocal_ block because some side effect need to propagate to the calling environment. Therefore, when recursively chaining several commands, it may sometimes make sens to break propagation of side effect at some point in hierarchy, and this can be achieved by using the _RunLocal.bat_ script.

The other usage is in testing. Some scripts have intended side effects, such as _SetScriptReferences.bat_ or _SetVar..bat_. Sometimes when troubleshooting issues ans debugging or testing such scripts in a console, we want to run them in sequences but want to preserve intact environment between successive calls, such that each group of tests would run under the same conditions (without having specific variables set by these scripts before running the next test). The _SetLocal_ script may come handy in such situations.

**Usage**:

> _SetLocal.bat_ _EmbeddedCommand <arg 1 arg 2 ....>  
> _
> 
> > Executes the command _EmbeddedCommand_, passing it the optional command-line arguments when defined (the optional arguments _arg1_, _arg2_, etc.), within the _**setlocal**_ / _**endlocal**_ block, such that changes such as environment variables defined or changed by the script are not propagated to the calling environment.  

  

### SetScriptReferences.bat

Sets a set of predetermined environment variables to the paths of the current locally cloned _IGLibScripts_ repository and some commonly used scripts within that are included in the repository. The assignment of environment variables defined by the script propagate back to the caller's environment.

This script is commonly used in bootstrapping scripts, which take care that the _IGLibScripts_ is cloned at known location such that its scripts can be used. There are several advantages in putting script paths into environment variables. The scripts can in this way be run in shorter form, e.g.:  
    _<u>"%UpdateRepo%"</u> .\\SettingsIGLibCore <u>"%SetVar%"</u> ModuleDir ..\\modules\\IGLibCore_

The second advantage is that reasonable attempts will be made that names of these meaningful variables will remain unchanged, while relative locations of the corresponding scripts within the _IGLibScripts_ repository or script names may change often.  
If a location within the _IGLibScripts_ repository or name of a certain script would change, the _SetScriptReferences.bat_ would be updated accordingly to reflect the new path (if not, this would be a bug). In case that some variable name is found strange and would be changed, the previous name can still remain set in the script for some time.

The following environment variables are defined by the script:

> _**IGLibScripts**_ is set to the absolute path path of the cloned _IGLibScripts_ repository from which the batch script was called.  
> _**UpdateRepo**_ is set to the full absolute path of the script _UpdateRepo.bat_ contained in the locally cloned _IGLibScripts_ repository from which the _SetScriptReferences_ script was called.  
> _**SetVar**_ is set to the absolute path of the _SetVar.bat_ script.  
> _**PrintRepoSettings**_ is set to the absolute path of the _PrintRepoSettings.bat_ script.  
> _**SetScriptReferences**_ is set to the absolute path of the _SetScriptReferences.bat_ script.  
> _**PrintScriptReferences**_ is set to the absolute path of the _PrintScriptReferences.bat_ script.  

  

### PrintScriptReferences.bat  

Prints values of environment variables that are set by _SetScriptReferences.bat_.  
**Usage**:  

> _PrintScriptReferences.bat  
> _
> 
> > Just prints the values of environment variables that are set by the _SetScriptReferences_ script.  
> 
> __PrintScriptReferences_.bat_ _EmbeddedCommand <arg 1 arg 2 ....>_  
> 
> > Beside printing the variables as described above, this also executes the command _EmbeddedCommand_, passing it the optional command-line arguments when defined (the optional arguments _arg1_, _arg2_, etc.). The command is executed before printing of variables is performed. This can be used e.g. to run the _SetScriptReferences_ script, which sets the variables, before they are printed. Execution of the _EmbeddedCommand_ is performed within the _**setlocal**_ / _**endlocal**_ block, such that changes such as environment variables defined or changed by the command are not propagated to the calling environment. This is particularly useful for testing.

