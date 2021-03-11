#!/bin/bash


HEROKU_TARBALL_LINK="https://cli-assets.heroku.com/heroku-v7.35.1/heroku-v7.35.1-linux-x64.tar.xz"
HEROKU_TARBALL_NAME="awesome_heroku_archive.tar.xz"
CHECK_HASH="47cc489af0190d9d43c3d6695330999e3be0d4d655a251e9cfe0c726ff6efd19"
# TODO : check hash and version from https://cli-assets.heroku.com/linux-x64 instead
LOCAL_HEROKU_LIB="$HOME/.local/lib/heroku"
LOCAL_HEROKU_SYMLINK="$HOME/.local/bin/heroku"

wget "$HEROKU_TARBALL_LINK" -O "/tmp/${HEROKU_TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${HEROKU_TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31mHeroku archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi

# Uninstall old version if exists
rm -rf $LOCAL_HEROKU_LIB || true
rm -rf $LOCAL_HEROKU_SYMLINK || true

# Install
mkdir -p $LOCAL_HEROKU_LIB
# Was done in case there is some day an archive containing something else than one heroku dir
tar x -C "$LOCAL_HEROKU_LIB" -f "/tmp/${HEROKU_TARBALL_NAME}"
mv ${LOCAL_HEROKU_LIB}/heroku/* $LOCAL_HEROKU_LIB
ln -s ${LOCAL_HEROKU_LIB}/bin/heroku $LOCAL_HEROKU_SYMLINK
