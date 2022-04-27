#!/bin/bash


NAME="node"
VERSION="v16.14.2"
NAME_AND_VERSION=$NAME"-"$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION"-linux-x64"
TARBALL_LINK="https://nodejs.org/dist/"$VERSION"/"$NAME_AND_STUFF".tar.xz"
TARBALL_NAME=$NAME_AND_STUFF".tar.xz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="e40c6f81bfd078976d85296b5e657be19e06862497741ad82902d0704b34bb1b"


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
ln -s ${LOCAL_STUFF}/$NAME_AND_STUFF/bin/npx ~/.local/bin/npx
