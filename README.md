# Quick setups and config files for different environments

## Windows
One script to setup a decent Windows environment from a clean install using Chocolatey
 - Checks Chocolatey installer certificate, must be sha256, thumbprint must be ok
 - No need to launch as admin, tries to elevate itself
 - Installs Firefox, Python, Atom, Cmder and git through Chocolatey
 - Installs magic-wormhole through pip


## MacOS
One script to setup a NativeScript / React Native dev environment for a regular user.  
It only requires an Admin to:
- Install XCode,
- Setup a directory as root with the correct rights (used by watchman)
This script was made to get a dev env as fast as possible (reusing pre-built watchman, patching it with install_name_tool for example)

## Linux
Most of my personal scripts, still not clean
