#!/bin/bash


function install-font {
  FONT_ZIP_LINK=$1
  FONT_ZIP_NAME=$2
  FONT_DIR="$HOME/.local/share/fonts"
  CHECK_HASH=$3

  mkdir -p $FONT_DIR

  wget "$FONT_ZIP_LINK" -O "/tmp/${FONT_ZIP_NAME}"
  HASH=$(sha256sum "/tmp/${FONT_ZIP_NAME}" | cut -d ' ' -f 1)
  if [ "$HASH" != "$CHECK_HASH" ]; then
    echo -e "\e[31mFont zip hash not matching. Possible corruption attempt.\e[0m"
    exit
  fi
  #unzip "/tmp/${FONT_ZIP_NAME}" -d "${FONT_DIR}"
  unzip "/tmp/${FONT_ZIP_NAME}" -d "/tmp/${FONT_ZIP_NAME}DIR"
  cp "/tmp/${FONT_ZIP_NAME}DIR"/*.ttf "${FONT_DIR}"
  chmod 744 "${FONT_DIR}"
  chmod 644 "${FONT_DIR}"/*
}


install-font \
  "http://fonts.google.com/download?family=Montserrat" \
  "Montserrat.zip" \
  "590e5db0ff06496d7264fc44a6d11fbd2e0e8af396669cf37248f22e2a781203"
