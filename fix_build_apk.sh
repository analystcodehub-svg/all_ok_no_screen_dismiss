#!/bin/bash
MAX_TRIES=10
for i in $(seq 1 $MAX_TRIES); do
  echo "Try $i..."
  flutter build apk --release > build_log_apk.txt 2>&1
  if grep -q "java.nio.file.NoSuchFileException" build_log_apk.txt; then
    MISSING_FILE=$(grep "NoSuchFileException" build_log_apk.txt | grep -o "/home/oem/.*gradle-1.0.0.jar" | head -1)
    if [ ! -z "$MISSING_FILE" ]; then
      echo "Fixing missing file: $MISSING_FILE"
      mkdir -p "$(dirname "$MISSING_FILE")"
      cp /home/oem/flutter/packages/flutter_tools/gradle/build/libs/gradle-1.0.0.jar "$MISSING_FILE"
      continue
    fi
  fi
  if grep -q "Built build/app/outputs/flutter-apk/app-release.apk" build_log_apk.txt; then
    echo "SUCCESS"
    cp build/app/outputs/flutter-apk/app-release.apk /home/oem/Desktop/SajniRe-release.apk
    exit 0
  fi
  echo "Failed for another reason."
  cat build_log_apk.txt
  exit 1
done
