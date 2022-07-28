#!/bin/bash

# TODO : The scripts themselves don't check checksums, so...             : TODO #
# TODO : https://docs.nativescript.org/environment-setup.html#macos-ios  : TODO #
# TODO : https://reactnative.dev/docs/environment-setup - iOS guide      : TODO #

echo "This will setup a dev﹡env for a fresh regular MacOS user."
echo "                         ﹡(NativeScript / React Native)"
echo "Only prerequisites are"
echo "  - XCode and other build tools have been installed"
echo "  - You"
echo "    - created a /usr/local/var/run/watchman directory"
echo "    - chmod 2777 it so that any user can create its state directory inside"
echo "    This can actually be done after the execution of this script"
read -p "Press enter to continue, ctrl-C to quit"

set -e
cd ~
touch .zshrc
chmod +x .zshrc

mkdir -p ~/.local/bin ~/.local/external
echo 'export PATH="$HOME"/.local/bin:"$PATH"' >> ~/.zshrc
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

# TODO : Secure
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
. "$HOME"/.zshrc
nvm install 14

# temurin11 is recommended by NS doc, zulu11 by React Native, we don't build on M1 macs for now, so...
# https://whichjdk.com/
TEMURIN_PATH=~/.local/external/adoptium/temurin
TEMURIN_PATH_NH=.local/external/adoptium/temurin
TEMURIN_FILE=OpenJDK11U-jdk_x64_mac_hotspot_11.0.16_8.tar.gz
mkdir -p $TEMURIN_PATH
curl -Lo $TEMURIN_PATH/$TEMURIN_FILE https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.16%2B8/$TEMURIN_FILE
cd "$TEMURIN_PATH"
tar xzvf "$TEMURIN_FILE"
cd -
# Will look for $JAVA_HOME/bin/java
echo 'export JAVA_HOME="$HOME"/'"$TEMURIN_PATH_NH"'/jdk-11.0.16+8/Contents/Home' >> ~/.zshrc
echo 'export PATH="$HOME"/'"$TEMURIN_PATH_NH"'/jdk-11.0.16+8/Contents/Home/bin:"$PATH"' >> ~/.zshrc
. "$HOME"/.zshrc

EXT_ANDROID_SDK_NH=.local/external/android-sdk/
mkdir -p ~/"$EXT_ANDROID_SDK_NH"
# TODO : SHA256(commandlinetools-mac-8512546_latest.zip)= f810107f9e8907edc83859eb2560a62e9c3c87f2d1ae4a3d517f80234fff3f11
curl -Lo ~/"$EXT_ANDROID_SDK_NH"/commandlinetools-mac-8512546_latest.zip https://dl.google.com/android/repository/commandlinetools-mac-8512546_latest.zip
cd ~/"$EXT_ANDROID_SDK_NH"
unzip commandlinetools-mac-8512546_latest.zip
cd -
echo 'export PATH="$HOME"/'"$EXT_ANDROID_SDK_NH"'/cmdline-tools/bin:"$PATH"' >> ~/.zshrc

ANDROID_ROOT="$HOME"/Library/Android/sdk
echo 'export ANDROID_SDK_ROOT="$HOME"/Library/Android/sdk' >> ~/.zshrc
echo 'export ANDROID_HOME="$ANDROID_SDK_ROOT"' >> ~/.zshrc  # This one is used by Native Script
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/emulator' >> ~/.zshrc
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools' >> ~/.zshrc
. "$HOME"/.zshrc

# As React Native requires the Android 12 (S) SDK (API Level 31) in particular to build a React Native app with native code.
sdkmanager --sdk_root="$ANDROID_ROOT" platforms\;android-31
# Choose 1 of
# - system-images;android-31;default;arm64-v8a       ARM 64 v8a System Image
# - system-images;android-31;default;x86_64          Intel x86 Atom_64 System Image
# - system-images;android-31;google_apis;arm64-v8a   Google APIs ARM 64 v8a System Image
# - system-images;android-31;google_apis;x86_64      Google APIs Intel x86 Atom_64 System Image
sdkmanager --sdk_root="$ANDROID_ROOT" "system-images;android-31;default;x86_64"
sdkmanager --sdk_root="$ANDROID_ROOT" "build-tools;31.0.0"
sdkmanager --sdk_root="$ANDROID_ROOT" "platform-tools"
# TODO : Android Virtual Device ?

npm install -g nativescript
. "$HOME"/.zshrc

# Check no issues
ns doctor android
