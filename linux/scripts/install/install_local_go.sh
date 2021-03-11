#!/bin/bash


NAME="go"
VERSION="1.15.2"
NAME_AND_VERSION=$NAME""$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION".linux-amd64"
TARBALL_LINK="https://golang.org/dl/"$NAME_AND_STUFF".tar.gz"
TARBALL_NAME=$NAME_AND_STUFF".tar.gz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="b49fda1ca29a1946d6bb2a5a6982cf07ccd2aba849289508ee0f9918f6bb4552"


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
