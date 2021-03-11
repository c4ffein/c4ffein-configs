#!/bin/bash


NAME="node"
VERSION="v12.18.3"
NAME_AND_VERSION=$NAME"-"$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION"-linux-x64"
TARBALL_LINK="https://nodejs.org/dist/"$VERSION"/"$NAME_AND_STUFF".tar.xz"
TARBALL_NAME=$NAME_AND_STUFF".tar.xz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="b79e02e48d0a1ee4cd4ae138de97fda5413542f2a4f441a7d0e189697b8da563"


mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31m"$NAME" archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
tar x -C "$LOCAL_STUFF" -f "/tmp/${TARBALL_NAME}"

rm ~/.local/bin/node
rm ~/.local/bin/npm
rm ~/.local/bin/npx

ln -s ${LOCAL_STUFF}/$NAME_AND_STUFF/bin/node ~/.local/bin/node
ln -s ${LOCAL_STUFF}/$NAME_AND_STUFF/bin/npm ~/.local/bin/npm
ln -s ${LOCAL_STUPP}/$NAME_AND_STUFF/bin/npx ~/.local/bin/npx
