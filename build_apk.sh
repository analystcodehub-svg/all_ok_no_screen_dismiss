#!/bin/bash
export JAVA_HOME=~/.local/jdk/jdk-17.0.2
export PATH=$JAVA_HOME/bin:$PATH
/home/oem/flutter/bin/flutter clean
/home/oem/flutter/bin/flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk /home/oem/Desktop/SajniRe_APK/SajniRe-release-latest.apk
echo "DONE"
