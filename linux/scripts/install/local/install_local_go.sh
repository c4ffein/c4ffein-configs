#!/bin/bash


NAME="go"
VERSION="1.19.3"
NAME_AND_VERSION=$NAME""$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION".linux-amd64"
TARBALL_LINK="https://golang.org/dl/"$NAME_AND_STUFF".tar.gz"
TARBALL_NAME=$NAME_AND_STUFF".tar.gz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="74b9640724fd4e6bb0ed2a1bc44ae813a03f1e72a4c76253e2d5c015494430ba"


mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31m"$NAME" archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
tar x -C "$LOCAL_STUFF" -f "/tmp/${TARBALL_NAME}"

rm ~/.local/bin/go
rm ~/.local/bin/gofmt

ln -s ${LOCAL_STUFF}/go/bin/go ~/.local/bin/go
ln -s ${LOCAL_STUFF}/go/bin/gofmt ~/.local/bin/gofmt
