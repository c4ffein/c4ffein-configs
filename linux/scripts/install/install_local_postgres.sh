#!/bin/bash


PGSQL_TARBALL_LINK="https://get.enterprisedb.com/postgresql/postgresql-10.10-1-linux-x64-binaries.tar.gz"
PGSQL_TARBALL_NAME="postgresql-10.10-1-linux-x64-binaries.tar.gz"
export PGDATA="$HOME/databases/pgsql_data"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="e67469c797311088aa1e4dbbfaaaeb0017436934664b2899241311a03275d933"

mkdir -p $LOCAL_STUFF
mkdir -p $PGDATA

wget "$PGSQL_TARBALL_LINK" -O "/tmp/${PGSQL_TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${PGSQL_TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31mPostgreSQL archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
tar x -C "$LOCAL_STUFF" -f "/tmp/${PGSQL_TARBALL_NAME}"

"$LOCAL_STUFF/pgsql/bin/initdb"
# "$LOCAL_STUFF/pgsql/bin/pg_ctl" start
# "$LOCAL_STUFF/pgsql/bin/psql" -h localhost postgres # to connect

grep -qi PGDATA ~/.bashrc || echo "export PGDATA=$(printf "%q" "$PGDATA")" >> "$HOME/.bashrc"
grep -qi "$LOCAL_STUFF/pgsql" ~/.bashrc || echo "export PATH=$LOCAL_STUFF/pgsql/bin:\$PATH" >> "$HOME/.bashrc"
