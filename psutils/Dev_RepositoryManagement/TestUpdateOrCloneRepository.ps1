
# This contains PowerShell commands for testing the UpdateOrCloneRepository.ps1.
# Open the PowerShell CLI in the directory of this script and copy-paste commands
# from this file, then verify the results.

# Set variables containing repository parameters for IGLibScripts:
./SetUpdateOrClone_IGLibScripts.ps1
./PrintSettingsUpdateOrClone.ps1
# Resets variables containing repository parameters to null:
./SetUpdateOrClone_Null.ps1
./PrintSettingsUpdateOrClone.ps1

# Cloning repository without specifying the checkout branch, into nested directory:
# Before, either remove the clone directory, or let it exist.
# Both if directory does not exist or it exists but it is empty,
# the remote repository should be cloned into the repos/IGLibScripts directory.
./UpdateOrCloneRepository.ps1 -Directory "repos/IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"

# Cloning repository from a directory different from script directory, with a
# relative path.
# Expected: Relative path resolves relative to the current directory.
Set-Location TestScripts  # change to directory different than script directory
../UpdateOrCloneRepository.ps1 -Directory "repos/IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
Set-Location ..  # Change back to the initial directory

# Cloning repository from a directory different from script directory, with a
# relative path.
# Expected: Relative path resolves relative to the base directory.
Set-Location TestScripts  # change to directory different than script directory
../UpdateOrCloneRepository.ps1 -Directory "repos/IGLibScripts" `
    -BaseDirectory "../"  `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
Set-Location ..  # Change back to the initial directory

# Cloning or updating with a different branch than the default one:
# Remove the repo directory before executing, or keep it with another ref
# check out to observe the effect.
# Expected: in all cases the specified ref should be checked out. 
./UpdateOrCloneRepository.ps1 -Directory "IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -ref "release/latestrelease"

# Cloning or updating with ABSOLUTE Directory path
# WARNING: Change directory path according to location on your machine!
# Expected: clone or update should be performed on the correct (specified) directory.
./UpdateOrCloneRepository.ps1 `
    -Directory "u:/ws/ws/other/ajgor/iglibmodules/IGLibSandbox/scripts/IGLibScripts1" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -ref "release/latestrelease"

# Cloning or updating with additional remote specified:
# Remove or not the repository before executing.
# Expected: The remotes should be added.
./UpdateOrCloneRepository.ps1 -Directory "IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -addressSecondary "https://XXXgithub.com/ajgorhoe/IGLib.modules.IGLibScripts.git"

./UpdateOrCloneRepository.ps1 -Directory "IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -addressTertiary "d:\backup_sync\bk_code\git\ig\misc\iglib_modules\IGLibCore\" `
    -remoteTertiary "mylocalrepo"


# PROVIDING PARAMETERS (all or part od them) VIA PowerShell FILES / VARIABLES:
# Agreed variable names are used to provide parameter values (the same as
# parameter names, but with a specified prefix - search the script for prefix!).
# When setting parameters in a PowerShell script, the script must be run with .
# (e.g. . ./SettingsCore.ps1) such that variables are reflected in the caller 
# environment.
# In order for agreed global variables to provide values of unspecified parameters,
# both the -DefaultFromVars and -Execute switches must be on.

# Cloning or updating with VARIABLES specifying PARAMETERS:
# Variables CurrentRepo_Address and CurrentRepo_Directory defines repository address
# and a relative path to the cloning directory w.r. the script directory.
# Expected: the repository with specified address is cloned (or updated by Git pull)
#   in the specified directory relative to the script directory.
# The lines below must be run from the PowerShell command-line:
$CurrentRepo_Directory = "IGLibScripts";
$CurrentRepo_Address = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git";
./UpdateOrCloneRepository.ps1 -DefaultFromVars -Execute

# Cloning or updating with VARIABLES that define script parameters IN THE SETTINGs
# SCRIPT. The settings script must be run with DOT AND SPACE preceding the script 
# file path.
# Expected: Parameters take the values specified by global variables set by the 
#   settings script.
# The lines below must be run from the PowerShell command-line:
. ./TestSettingsIGLibScript.ps1  # this sets variables representing parameters
./UpdateOrCloneRepository.ps1 -DefaultFromVars -Execute

# Cloning or updating by setting VARIABLES that define script parameters while
# some script parameters are also specified explicitly.
# The specified SCRIPT PARAMETERS take PRIORITY over values in variables.
# Expected: Parameters take the values specified by global variables set before 
#   the script is run, except those parameters that are stated explicitly. E.g.,
#   the clone directory is set to "IGLibScripts11" defined as script parameter,
#   rather than "IGLibScript" defined in a variable.
# The lines below must be run from the PowerShell command-line:
$CurrentRepo_Directory = "IGLibScripts";
$CurrentRepo_Address = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git";
./UpdateOrCloneRepository.ps1 -Directory "IGLibScripts11" -DefaultFromVars -Execute


# USING the cloning/updating FUNCTION instead of script:
# You can run teh script just to get the function defined, and then run the 
# function instead of the script. Rules are similar, except parameter names have 
# camel case and there relative directory paths are with respect to the current 
# directory rather than script's directory (because execution is not bound to
# the update script).

# Cloning / updating the repository by calling the function UpdateOrCloneRepository
# instead of running the script with the same name. However, we need to run the
# script with no parameters first, such that the script does not get executed.
# This defines the update/clone function, which we call next, providing it with
# the necessary parameters.
# Warning: the script must be called with the preceding dot and space, such that
# the function defined in the script is remains defined in the calling context.
# Expected: Function performs the task in a similar way than the script would.
#   Parameters must be specified as camel case, and relative directories are stated
#   with respect to the current directory rather than script directory.
. ./UpdateOrCloneRepository.ps1    # running of the script defines the function
UpdateOrCloneRepository -directory "IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"


# Cloning or Updating using specific script for a repository (Update_IGLibScripts.ps1):
# The specific update script always resolves the directories relative to script
# directory.

# Cloning from the same directory that contains the custom script:
# Repository directory is specified as relative path, which should be resolved
# relative to script directory.
# Expected results: The IFLib repository should be cloned or updated at the path 
# specified in the specific update script, with relative path resolved relative
# to the custom script directory.
./Update_IGLibScripts.ps1

# Calling the specific (custom) update / clone script from a different directory:
# Expected: the repository directory should have the same path regardless of
# the current directory at the time when the script is called.
Set-Location TestScripts   # change to a directory different than script directory
../Update_IGLibScripts.ps1
Set-Location ..
