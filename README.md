# Quick setups and config files for different environments

## `home`
My portable .dotfiles, should be compatible with both Linux and MacOS, and even Windows for most features
The target is bootstrapping a minimalist environment with Alacritty and Neovim


## `bloated`
Alternate .dotfiles for versioning my full Linux desktop - including Hyprland and scripts to install Flatpaks


## `windows`
### Windows 10
Legacy: Used this script to setup Windows environments from clean installs using Chocolatey
### Windows 11
Just installs Neovim and Alacritty through WinGet


## `macos`
One script to setup a NativeScript / React Native dev environment for a regular user.  
It only requires an Admin to:
- Install XCode
- Setup a directory as root with the correct rights (used by watchman)

This script was made to get a dev env as fast as possible (reusing pre-built watchman, patching it with install_name_tool for example)


## `linux`
Some of my old personal scripts, still not clean
