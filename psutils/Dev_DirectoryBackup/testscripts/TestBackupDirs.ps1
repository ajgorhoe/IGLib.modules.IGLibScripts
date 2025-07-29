
# This contains PowerShell commands for manually testing the BackupDir.ps1.
# Open the PowerShell CLI in the directory of this script and copy-paste
# commands from this file, then verify the results.

# Removing a directory recursively:
#   Remove-Item -Recurse -Force -Path "path/to/directory"   # replace the path!
#   Remove-Item -Recurse -Force -Path "./backups/BackupSourceBasic/"
# Copying a directory recursively:
#   Copy-Item "path/to/source" "path/to/destination" -Recurse   # replace the paths!
#   Copy-Item "./sourcedirs/BackupSourceBasic/" "./backups/BackupSourceBasic/" -Recurse
#   Copy-Item "./sourcedirs/BackupSourceBasic/" "./backups/" -Recurse
# Alternativie - robocopy (more consistent & idempotent):
#   robocopy "path/to/source" "path/to/destination" /E   # replace the paths!
#   robocopy "./sourcedirs/BackupSourceBasic/" "./backups/BackupSourceBasic/" /E
#   robocopy "./sourcedirs/BackupSourceBasic/" "./backups/" /E

# TEST CASES:

# Backup a directory (BackupSourceBasic) with usual mode (without the InPlace 
# option) and with relative paths, target dir. not existing:
# Remove eventual existing backup directory:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
# Run backup script:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/BackupSourceBasic"
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
# Run backup script with the same parameters again:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/BackupSourceBasic"
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic


# Backup a directory (BackupSourceBasic) with usual mode (without the InPlace 
# option) and with ABSOLUTE PATHS, target dir not existing:
# Remark: adapt the absolute path according to the absolute path of the test 
# directory after repository checkout!
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
../BackupDir.ps1 "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts\sourcedirs/BackupSourceBasic" "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts/backups/BackupSourceBasic"





# =================================================

