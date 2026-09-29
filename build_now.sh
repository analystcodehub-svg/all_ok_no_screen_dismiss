#!/bin/bash
set -e
source "/usr/local/sdkman/bin/sdkman-init.sh"
sdk use java 17.0.10-tem
export ANDROID_HOME=/home/codespace/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/home/codespace/flutter/bin

cd /workspaces/healthy2
flutter clean
flutter pub get
flutter build apk --release
