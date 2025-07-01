
# This contains PowerShell commands for manually testing the BackupDir.ps1.
# Open the PowerShell CLI in the directory of this script and copy-paste
# commands from this file, then verify the results.

# Recursively remove a directory:
#   Remove-Item -Path "path\to\directory" -Recurse -Force

# Backup a directory (BackupSourceBasic) with usual mode (without the InPlace 
# option) and with relative paths
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
. ../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/BackupSourceBasic"


# Backup a directory (BackupSourceBasic) with usual mode (without the InPlace 
# option) and with ABSOLUTE PATHS
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
. ../BackupDir.ps1 "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts\sourcedirs/BackupSourceBasic" "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts/backups/BackupSourceBasic"

# =================================================

