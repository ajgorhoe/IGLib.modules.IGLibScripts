
# This contains PowerShell commands for testing the UpdateOrCloneRepository.ps1.
# Open the PowerShell CLI in the directory of this script and copy-paste commands
# from this file, then verify the results.

# Cloning repository without specifying the checkout branch, into nested directory:
# Before, either remove the clone directory, or let it exist.
# Both if directory does not exist or it exists but it is empty,
# the remote repository should be cloned into the directory.
./UpdateOrCloneRepository.ps1 -Directory "repos/IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"

# Cloning or updating with a different branch than the default one:
# Remove the repo directory before executing, or keep it with another ref
# check out to observe the effect.
# Expected: in all cases the specified ref should be checked out. 
./UpdateOrCloneRepository.ps1 -Directory "IGLibScripts" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -ref "release/latestrelease"

# Cloning or updating with ABSOLUTE Directory path
# WARNING: Change directory path according to location on your machine!
# Expected: clone or updae should be performed on the correct (specified) directory.
./UpdateOrCloneRepository.ps1 `
    -Directory "u:/ws/ws/other/ajgor/iglibmodules/IGLibSandbox/scripts/IGLibScripts1" `
    -address "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git" `
    -ref "release/latestrelease"
