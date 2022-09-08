#!/bin/bash

# TODO : The scripts themselves don't check checksums, so...             : TODO #
# TODO : https://docs.nativescript.org/environment-setup.html#macos-ios  : TODO #
# TODO : https://reactnative.dev/docs/environment-setup - iOS guide      : TODO #

echo "This will setup a dev﹡env for a fresh regular MacOS user."
echo "                           ﹡(NativeScript / React Native)"
echo "Only prerequisites are"
echo "  - XCode and other build tools have been installed"
echo "    - \`xcode-select --install/\` for a CommandLineTools only install"
echo "    - Warning : you may have to install the whole Xcode and not just"
echo "      the Command Line Tools for some deps, e.g. Capacitor"
echo "    - Select an Xcode dev tools path using xcode-select"
echo "      - Use the Xcode one if possible, otherwise will be as if it is not there"
echo "      - \`xcode-select -s /Applications/Xcode.app/Contents/Developer\` or else"
echo "      - \`sudo xcode-select -switch /Library/Developer/CommandLineTools\`"
echo "  - You"
echo "    - created a /usr/local/var/run/watchman directory"
echo "    - chmod 2777 it so that any user can create its state directory inside"
echo "    This can actually be done after the execution of this script"
read -p "Press enter to continue, ctrl-C to quit"


ENVSH_NH=.local/env.sh
ENVSH="$HOME"/"$ENVSH_NH"
TEMURIN_PATH_NH=.local/external/adoptium/temurin
export GODIR=".local/external/go"


# Friendly reminder mamene
# % touch a\ b c
# % k=a\ b; echo $k
# a b
# % k=a\ b; ls $k 
# a b
# % k=a\ b; ls ${k}
# a b
# % bash
# bash-3.2$ k=a\ b; ls ${k}
# ls: a: No such file or directory
# ls: b: No such file or directory
# bash-3.2$ k=a\ b; ls "${k}"
# a b


set -e
cd ~
mkdir -p ~/.local/bin ~/.local/external
touch .zshrc "$ENVSH"
chmod +x .zshrc "$ENVSH"

echo 'export PATH="$HOME"/.local/bin:"$PATH"'                                            > "$ENVSH"
echo 'export JAVA_HOME="$HOME"/'"$TEMURIN_PATH_NH"'/jdk-11.0.16+8/Contents/Home'        >> "$ENVSH"
echo 'export PATH="$HOME"/'"$TEMURIN_PATH_NH"'/jdk-11.0.16+8/Contents/Home/bin:"$PATH"' >> "$ENVSH"
echo 'export ANDROID_SDK_ROOT="$HOME"/Library/Android/sdk'                              >> "$ENVSH"
echo 'export PATH="$ANDROID_SDK_ROOT"/cmdline-tools/bin:"$PATH"'                        >> "$ENVSH"
echo 'export ANDROID_HOME="$ANDROID_SDK_ROOT"'                                          >> "$ENVSH"  # Native Script...
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/emulator'                                     >> "$ENVSH"
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools'                               >> "$ENVSH"
echo "export GOROOT="'"$HOME"'/"$GODIR"/goroot                                          >> "$ENVSH"
echo "export GOPATH="'"$HOME"'/"$GODIR"/gopath                                          >> "$ENVSH"
echo "export PATH="'${PATH}:${GOROOT}/bin:$GOPATH/bin'                                  >> "$ENVSH"
echo "export GEM_HOME="'"$HOME"'/.local/external/rubygems/gems                          >> "$ENVSH"
echo "export PATH="'${PATH}:"$HOME"/.local/external/rubygems/gems/bin'                  >> "$ENVSH"
echo ''                                                                                 >> "$ENVSH"
echo 'alias gr=grep'                                                                    >> "$ENVSH"
echo 'alias la="ls-lah"'                                                                >> "$ENVSH"

echo '. "$HOME"/'"$ENVSH_NH"                                                            >> ~/.zshrc
. "$HOME"/.zshrc


mkdir -p ~/.local/external/watchman
# TODO : sha256 76102d01e213e24ff46cf725d5fd4473abdd50298de3deced77c12b8fd22f73e
curl -Lo ~/.local/external/watchman/watchman-v2022.07.25.00-macos.zip https://github.com/facebook/watchman/releases/download/v2022.07.25.00/watchman-v2022.07.25.00-macos.zip
cd ~/.local/external/watchman
unzip watchman-v2022.07.25.00-macos.zip
# There are no spaces in set lib paths, so we safe, so we can code dirty :)
set +e
cd -; cd ~/.local/external/watchman/watchman-v2022.07.25.00-macos
for f in */*; do
  install_name_tool -add_rpath @executable_path/. "$f"
  x=$(otool -l "$f" | grep "/usr/local/lib")
  for t in $x; do
    if [[ $t == /usr/local/lib* ]]; then
      endin=$(echo $t | cut -c 12-)
      np=@rpath/../$endin
      echo patching $f $t $np
      install_name_tool -change $t $np $f
    fi
  done
done
set -e
ln -s "$(pwd)"/bin/watchman ~/.local/bin/watchman
cd -

# Cocoapods
mkdir -p "$GEM_HOME"
gem install cocoapods

# Go
mkdir -p "$GOPATH"
rm -rf "$GOROOT"
curl -s https://dl.google.com/go/go1.19.darwin-amd64.tar.gz | tar zxf - -C "$HOME"/"$GODIR"
mv "$HOME"/"$GODIR"/go "$HOME"/"$GODIR"/goroot


# TODO : Secure
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
. "$HOME"/.zshrc
nvm install 14

# temurin11 is recommended by NS doc, zulu11 by React Native, we don't build on M1 macs for now, so...
# https://whichjdk.com/
TEMURIN_PATH=~/"$TEMURIN_PATH_NH"
TEMURIN_FILE=OpenJDK11U-jdk_x64_mac_hotspot_11.0.16_8.tar.gz
mkdir -p $TEMURIN_PATH
curl -Lo $TEMURIN_PATH/$TEMURIN_FILE https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.16%2B8/$TEMURIN_FILE
cd "$TEMURIN_PATH"
tar xzvf "$TEMURIN_FILE"
cd -
# Will look for $JAVA_HOME/bin/java

EXT_ANDROID_SDK_NH=Library/Android/sdk
mkdir -p "$ANDROID_SDK_ROOT"  # Some tools make you use Android Studio, which could be confused... Need it here, with `cmdline-tools` in it
# TODO : SHA256(commandlinetools-mac-8512546_latest.zip)= f810107f9e8907edc83859eb2560a62e9c3c87f2d1ae4a3d517f80234fff3f11
curl -Lo "$ANDROID_SDK_ROOT"/commandlinetools-mac-8512546_latest.zip https://dl.google.com/android/repository/commandlinetools-mac-8512546_latest.zip
cd "$ANDROID_SDK_ROOT"
unzip commandlinetools-mac-8512546_latest.zip
cd -


# As React Native requires the Android 12 (S) SDK (API Level 31) in particular to build a React Native app with native code.
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" platforms\;android-31
# Choose 1 of
# - system-images;android-31;default;arm64-v8a       ARM 64 v8a System Image
# - system-images;android-31;default;x86_64          Intel x86 Atom_64 System Image
# - system-images;android-31;google_apis;arm64-v8a   Google APIs ARM 64 v8a System Image
# - system-images;android-31;google_apis;x86_64      Google APIs Intel x86 Atom_64 System Image
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "system-images;android-31;default;x86_64"
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "build-tools;31.0.0"
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools"
# TODO : Android Virtual Device ?

npm install -g nativescript
. "$HOME"/.zshrc

# Check no issues
ns doctor android
