#!/usr/bin/env pwsh

# This script restarts the Windows' Explorer process. This is sometimes
# necessary after settings that govern Explorer behavior have been changed, 
# e.g. by modifying registry keys.

Stop-Process -Name explorer -Force
Start-Process explorer

