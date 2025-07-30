
# This contains PowerShell commands for manually testing the BackupDir.ps1.
# Open the PowerShell CLI in the directory of this script and copy-paste
# commands from this file, then verify the results.

# Removing a directory recursively:
#   Remove-Item -Recurse -Force -Path "path/to/directory"   # replace the path!
#   Remove-Item -Recurse -Force -Path "./backups/BackupSourceBasic/"
# Copying a directory recursively:
# Warning: inconsistent path meaning for target path, dependent on whether it exists!
#   Copy-Item "path/to/source" "path/to/destination" -Recurse   # replace the paths!
#   Copy-Item "./sourcedirs/BackupSourceBasic/" "./backups/BackupSourceBasic/" -Recurse
#   Copy-Item "./sourcedirs/BackupSourceBasic/" "./backups/" -Recurse
# Alternativie - robocopy (more consistent & idempotent):
# Remark: more consistent target path interpretation: always path to the copy of
# source, not its parent directory. Options: /E — copy subdirs including empty
# /XO — exclude older files (copy only if source is newer), /NFL / /NDL — reduce log noise
#   robocopy "path/to/source" "path/to/destination" /E   # replace the paths!
#   robocopy "./sourcedirs/BackupSourceBasic/" "./backups/BackupSourceBasic/" /E
#   robocopy "./sourcedirs/BackupSourceBasic/" "./backups/" /E

# TEST CASES:

# COMPLETE COPY mode (without -InPlace):


# Backup a directory (BackupSourceBasic) without the -InPlace option and with
# relative paths, backup does not exist, target dir. (parent dir. of backup) exists,
# and THERE IS 1 BACKUP COPY KEPT (-NumCopies = 1):
# Remove eventual existing backup directory:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
# Run backup script (1st time):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 2
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
# Run backup script with the same parameters again (2nd time):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 2
robocopy "./backups/BackupSourceBasic/Dir1" "./backups/BackupSourceBasic/Dir1_copy"
# EXPECTED result: backups/BackupSourceBasic should contain a copy of sourcedirs/BackupSourceBasic with added Dir1_copy
#   plus there is ONE COPY, backups/BackupSourceBasic_01
# Run backup script with the same parameters again (3rd time):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 2
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
#   plus there are TWO COPIES, BackupSourceBasic_01 and BackupSourceBasic_02
#   plus added ./backups/BackupSourceBasic/Dir1_copy moves to BackupSourceBasic_01
# Run backup script with the same parameters again (4th time):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 2
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
#   plus there are TWO COPIES, BackupSourceBasic_01 and BackupSourceBasic_02
#   plus added ./backups/BackupSourceBasic/Dir1_copy moves to BackupSourceBasic_02
#   - DOES NOT WORK! - error!

# EXISTING/NONEXISTING backup directory
# Path resolution should be the same for both: target path specifies the parent directory of the 
# backup directory.

# Backup a directory (BackupSourceBasic) without the -InPlace option and with
# relative paths, backup  does not exist, target dir. (parent dir. of backup) exists:
# Remove eventual existing backup directory:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
# Run backup script:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups"
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
# Run backup script with the same parameters again:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups"
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic

# Backup a directory (BackupSourceBasic) without the -InPlace option and with
# relative paths, backup  does not exist, target dir. (parent dir. of backup) also not:
# Remove eventual existing backup directory:
Remove-Item -Path "backups/xx" -Recurse -Force  # first, remove the backup if it exists
# Run backup script:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/xx/yy"
# EXPECTED result: backups/xx/yy/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
# Run backup script with the same parameters again:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/xx/yy"
# EXPECTED result: backups/xx/yy/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic

# Backup a directory (BackupSourceBasic) without the -InPlace option and with
# relative paths, backup  does not exist, target dir. (parent dir. of backup) 
# exists, TARGET DIR (backup parent dir) has THE SAME NAME AS SOURCE dir:
# Remove eventual existing backup directory:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
# Run backup script:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/BackupSourceBasic"
# EXPECTED result: backups/BackupSourceBasic/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
# Run backup script with the same parameters again:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups/BackupSourceBasic"
# EXPECTED result: backups/BackupSourceBasic/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic

# ABSOLUTE paths:

# Backup a directory (BackupSourceBasic) with usual mode (without the InPlace 
# option) and with ABSOLUTE PATHS, target dir not existing:
# Remark: adapt the absolute path according to the absolute path of the test 
# directory after repository checkout!
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
../BackupDir.ps1 "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts\sourcedirs/BackupSourceBasic" "e:\wsorkspace\ws\other\iglibmodules\IGLibScripts\psutils\Dev_DirectoryBackup\testscripts/backups"





# =================================================

