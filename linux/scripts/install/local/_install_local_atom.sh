#!/bin/bash


# https://www.reddit.com/r/linux/comments/dvb43s/til_electron_requires_setuid_root_to_operate/f7bzhlb/?utm_source=reddit&utm_medium=web2x&context=3
# Chrome (and Electron) now requires a sandbox to run outside of certain dev scenarios. It's been this way for many years, and given the gigantic attack surface of a modern browser, it should be considered a good thing.
# The old way to do this involved a setuid helper binary to set it all up as root and then drop privileges back to your account. This is tricky, hard to get right and unnecessary now that there's improved namespace support in the kernel. The SUID sandbox has been on the way out for many years, being essentially disabled-by-default since 2015ish.
# Chrome now prefers to use the user namespace sandbox, but that requires a kernel from the past couple of years configured with the ability for users to set up their own namespaces. This is disabled by default in Debian and some other distros out of security concerns with it, but the holes in it have really dried up since unprivileged namespaces started to be used in production around late 2017-early 2018ish. At this point, the SUID sandbox is only a fallback that's not activated by default.
# So to fix this, you'd want to enable unprivileged user namespaces, even though the error doesn't hint at it at all. It'll stop it from getting there and is a generally safer alternative to letting a complicated and barely maintained sandbox app set things up as root.
# https://unix.stackexchange.com/questions/303213/how-to-enable-user-namespaces-in-the-kernel-for-unprivileged-unshare
# TODO : .local/share/Applications


NAME="atom"
VERSION="1.51.0"
TARBALL_NAME=$NAME"-amd64.tar.gz"
NAME_AND_STUFF=$NAME_AND_VERSION".linux-amd64"
TARBALL_LINK="https://github.com/atom/atom/releases/download/v${VERSION}/${TARBALL_NAME}"
LOCAL_STUFF="$HOME/Applications"
CHECK_HASH="35f9abe3e8d2c318d8113f90ca14d99b6c007c2c15baf5e1bf333e37fc998feb"


mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31m"$NAME" archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
mkdir -p "${LOCAL_STUFF}"
tar x -C "$LOCAL_STUFF" -f "/tmp/${TARBALL_NAME}"

rm ~/.local/bin/atom
ln -s "${LOCAL_STUFF}/atom-${VERSION}-amd64/atom" ~/.local/bin/atom
