
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

# IN-PLACE mode:

# Basic correctness of in-place backup:
# Prepare the state - we will back up from copies/ directory; remove any remainders of
# previous operations and prepare a copy to back up:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # remove the backup if it exists
Remove-Item -Path "copies/BackupSourceBasic" -Recurse -Force  # remove the copy that will be backed up
robocopy "./sourcedirs/BackupSourceBasic" "./copies/BackupSourceBasic" /E  # prepare a new copy by copying the source
# Perform in-place backup:
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -IsVerbose
# EXPECTED result: backups/BackupSourceBasic is exact copy of ./copies/BackupSourceBasic
# In the original directory, ADD a FILE and perform backup again:
Copy-Item "./copies/BackupSourceBasic/File0.1.txt" "./copies/BackupSourceBasic/AddedFile.txt" -Force
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -IsVerbose
# EXPECTED results: backups/BackupSourceBasic is exact copy of ./copies/BackupSourceBasic;
#   the file "./backups/BackupSourceBasic/AddedFile.txt" is added. Files that exist in
#   both source and backup directory and versions in source directory are not newer,
#   are NOT copied (which is seen in script's verbose output). 
# In the original directory, REMOVE a FILE and perform backup again:
Remove-Item "./copies/BackupSourceBasic/File0.2.txt" -Force
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -IsVerbose
# EXPECTED results: backups/BackupSourceBasic is exact copy of ./copies/BackupSourceBasic;
#   the file "./backups/BackupSourceBasic/File0.2.txt" is removed.

# Similar steps as above, but testing the OverwriteOlder and KeepNonexistent options:
# Prepare the state - we will back up from copies/ directory; remove any remainders of
# previous operations and prepare a copy to back up:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # remove the backup if it exists
Remove-Item -Path "copies/BackupSourceBasic" -Recurse -Force  # remove the copy that will be backed up
robocopy "./sourcedirs/BackupSourceBasic" "./copies/BackupSourceBasic" /E  # prepare a new copy by copying the source
# Perform in-place backup:
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -IsVerbose
# EXPECTED result: backups/BackupSourceBasic is exact copy of ./copies/BackupSourceBasic
# In the original directory, ADD a FILE and perform backup again, with OverwriteOlder set to true:
Copy-Item "./copies/BackupSourceBasic/File0.1.txt" "./copies/BackupSourceBasic/AddedFile.txt" -Force
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -OverwriteOlder -IsVerbose
# EXPECTED results: backups/BackupSourceBasic is exact copy of ./copies/BackupSourceBasic;
#   the file "./backups/BackupSourceBasic/AddedFile.txt" is added. Files that exist in
#   both source and backup directory are overwritten, which can be seen from verbose output. 
# In the original directory, REMOVE a FILE and perform backup again with -OverwriteOlder and -KeepNonexistent:
Remove-Item "./copies/BackupSourceBasic/File0.2.txt" -Force
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -OverwriteOlder -KeepNonexistent -IsVerbose
# EXPECTED results: backups/BackupSourceBasic is (almost) exact copy of ./copies/BackupSourceBasic, except for
#   the file "./backups/BackupSourceBasic/File0.2.txt", which is NOT removed from the backup although
#   the file is no longer contained in the source directory, due to -KeepNonexistent. Only files
#   that are older in the backup are overwritten.
# Finally, run this backup without the -KeepNonexistent option:
../BackupDir.ps1 "./copies/BackupSourceBasic" "./backups" -InPlace -OverwriteOlder -IsVerbose
# EXPECTED results: backups/BackupSourceBasic is EXACT COPY of ./copies/BackupSourceBasic;
#   the file "./backups/BackupSourceBasic/File0.2.txt" is REMOVED from the backup because
#   the file is no longer contained in the source directory, due to KeepNonexistent being false. 
# Only files
#   that are older in the backup are overwritten.


# ToDo: test parameters OverwriteOlder and -KeepNonexistent!


# COMPLETE COPY mode (without -InPlace):


# COPY ROTATION:

# Basic correctness of copy rotation:
# Backup a directory (BackupSourceBasic) without the -InPlace option and with
# relative paths, backup does not exist, target dir. (parent dir. of backup) exists,
# and THERE ARE 2 BACKUP COPIES KEPT (-NumCopies = 1):
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


# Different suffix length + removal of excessive copies when -NumCopies is reduced:
# Remove eventual existing backup directory:
Remove-Item -Path "backups/BackupSourceBasic" -Recurse -Force  # first, remove the backup if it exists
# Run backup script 4 times:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 3 -MinDigits 4
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 3 -MinDigits 4
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 3 -MinDigits 4
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 3 -MinDigits 4
# EXPECTED result: backups/BackupSourceBasic should contain exact copy of sourcedirs/BackupSourceBasic
#   Plus there should be 3 older copies, having name suffixes _0001, _0002, and _0003.
# Run backup script with the same parameters again (5th time):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 3 -MinDigits 4
# EXPECTED result: the situation should be the same as before (the additional copy generated
#   via copy rotation is removed because it exceeds the maximal number of copies)
# Run the backup script again, but now with reduced number of copies (2):
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 2 -MinDigits 4
# EXPECTED result: A fresh backup should be created again and copies should be rotated
#   (newer copies replacing older ones), but now there should be ONLY 2 additional 
#   copies (due to -NumCopies 2), as excessive copies should be removed.
# Run again, but reduce the number of additional copies to 0:
../BackupDir.ps1 "./sourcedirs/BackupSourceBasic" "./backups" -NumCopies 0 -MinDigits 4
# EXPECTED result: A fresh backup should be created again, but this time there should be
#   no additional backup copies because all copies should be removed (due to -NumCopies 0)



# EXISTING / NONEXISTING backup directory
# Target path meaning should be the same for both: target path specifies the parent directory 
# of the backup directory.

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

