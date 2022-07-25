#!/bin/bash

set -e
TRULY_SECRET=~/.local/share/secrets/TRULY_SECRET.sh  # Needs to be executable
type "$TRULY_SECRET" && . "$TRULY_SECRET"

PASSPHRASE="$SECRETS_PASS"
[ -z "$PASSPHRASE" ] && >&2 echo "No password found" && exit 4

TIMESTAMP=$(date +%s)
FILENAME=c4ffein-secrets-$TIMESTAMP
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p "temp"
mkdir -p "secrets"
mkdir temp/"$TIMESTAMP"
cd temp/"$TIMESTAMP"
mkdir "$FILENAME"
cp -r ~/.gnupg "$FILENAME"
cp -r ~/.ssh "$FILENAME"
cp -r ~/.local/share/password-store "$FILENAME"  # need gpg key to unlock
cp ~/.2fa "$FILENAME"  # This is bad, but it depends on the 2fa implem
tar -czvf "$FILENAME".tar.gz "$FILENAME"
[ -f ../../secrets/"$FILENAME".tar.gz.gpg ] && >&2 echo "$FILENAME".tar.gz.gpg ALREADY EXISTS && exit 7
gpg  -o ../../secrets/"$FILENAME".tar.gz.gpg  --pinentry-mode loopback --passphrase "$PASSPHRASE" -c "$FILENAME".tar.gz
