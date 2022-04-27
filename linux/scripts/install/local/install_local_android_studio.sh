#!/bin/bash


NAME="android-studio-ide"
VERSION="193.6626763"
NAME_AND_VERSION=$NAME"-"$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION"-linux"
TARBALL_LINK="https://redirector.gvt1.com/edgedl/android/studio/ide-zips/4.0.1.0/android-studio-ide-193.6626763-linux.tar.gz"
TARBALL_NAME=$NAME_AND_STUFF".tar.gz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="f2f82744e735eae43fa018a77254c398a3bab5371f09973a37483014b73b7597"


mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31m"$NAME" archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
tar x -C "$LOCAL_STUFF" -f "/tmp/${TARBALL_NAME}"

rm ~/.local/bin/android-studio

ln -s ${LOCAL_STUFF}/android-studio/bin/studio.sh ~/.local/bin/android-studio
