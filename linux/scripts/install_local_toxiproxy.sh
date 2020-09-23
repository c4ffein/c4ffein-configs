#!/bin/bash


NAME="toxiproxy"
VERSION="2.1.4"
NAME_AND_VERSION=$NAME""$VERSION
NAME_AND_STUFF=$NAME_AND_VERSION".linux-amd64"
TARBALL_LINK="https://github.com/Shopify/toxiproxy/releases/download/v${VERSION}/toxiproxy-cli-linux-amd64"
TARBALL_NAME=$NAME_AND_STUFF
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="451abcd548b83e5a73f2ac3b2c822874b29ff9ad3536c65e86d26b64b4283a4d"


mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31m"$NAME" archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
mkdir -p "${LOCAL_STUFF}/toxiproxy"
mv "/tmp/${TARBALL_NAME}" "${LOCAL_STUFF}/toxiproxy/${TARBALL_NAME}"
chmod 700 "${LOCAL_STUFF}/toxiproxy/${TARBALL_NAME}"

rm ~/.local/bin/toxiproxy

ln -s ${LOCAL_STUFF}/toxiproxy/${TARBALL_NAME} ~/.local/bin/toxiproxy
