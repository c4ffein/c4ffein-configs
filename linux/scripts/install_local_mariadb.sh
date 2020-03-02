#!/bin/bash


NAME_AND_VERSION="mariadb-10.4.12"
NAME_AND_STUFF=$NAME_AND_VERSION"-linux-glibc_214-x86_64"
TARBALL_LINK="https://downloads.mariadb.org/f/"$NAME_AND_VERSION"/bintar-linux-glibc_214-x86_64/"$NAME_AND_STUFF".tar.gz/from/http%3A//mirror.timeweb.ru/mariadb/?serve"
TARBALL_NAME=$NAME_AND_STUFF".tar.gz"
LOCAL_STUFF="$HOME/.local/external"
CHECK_HASH="351979bff45121aae38b742bcf656c0f42d8ac0b13487351ddc420cb23c6d02e"

mkdir -p $LOCAL_STUFF

wget "$TARBALL_LINK" -O "/tmp/${TARBALL_NAME}"
HASH=$(sha256sum "/tmp/${TARBALL_NAME}" | cut -d ' ' -f 1)
if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31mMariaDB archive hash not matching. Possible corruption attempt.\e[0m"
    exit
fi
tar x -C "$LOCAL_STUFF" -f "/tmp/${TARBALL_NAME}"

grep -qi "$LOCAL_STUFF/"$NAME_AND_STUFF ~/.bashrc || echo "export PATH=\$PATH:$LOCAL_STUFF/"$NAME_AND_STUFF"/bin" >> "$HOME/.bashrc"

if test -f "/etc/my.cnf" || test -f "/etc/mysql/my.cnf" || test -f "~/.my.cnf"; then
echo -e "\e[31mmy.cnf found.\e[0m"
echo "MariaDB searches for the configuration files '/etc/my.cnf' (on some systems '/etc/mysql/my.cnf') and '~/.my.cnf'. If you have an old my.cnf file (maybe from a system installation of MariaDB or MySQL) you need to take care that you don't accidentally use the old one with your new binary .tar installation."
echo "The normal solution for this is to ignore the my.cnf file in /etc when you use the programs in the tar file."
echo "This is done by creating your own .my.cnf file in your home directory and telling mysql_install_db, mysqld_safe and possibly mysql (the command-line client utility) to only use this one with the option '--defaults-file=~/.my.cnf'. Note that this has to be first option for the above commands!"
echo "Also applies to scripts - e.g., ./scripts/mysql_install_db --defaults-file=~/.my.cnf"
fi
