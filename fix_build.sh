#!/bin/bash
MAX_TRIES=10
for i in $(seq 1 $MAX_TRIES); do
  echo "Try $i..."
  flutter build appbundle > build_log.txt 2>&1
  if grep -q "java.nio.file.NoSuchFileException" build_log.txt; then
    MISSING_FILE=$(grep "NoSuchFileException" build_log.txt | grep -o "/home/oem/.*gradle-1.0.0.jar" | head -1)
    if [ ! -z "$MISSING_FILE" ]; then
      echo "Fixing missing file: $MISSING_FILE"
      mkdir -p "$(dirname "$MISSING_FILE")"
      cp /home/oem/flutter/packages/flutter_tools/gradle/build/libs/gradle-1.0.0.jar "$MISSING_FILE"
      continue
    fi
  fi
  if grep -q "Built build/app/outputs/bundle" build_log.txt; then
    echo "SUCCESS"
    cp build/app/outputs/bundle/release/app-release.aab /home/oem/Desktop/SajniRe-release-v15.aab
    exit 0
  fi
  echo "Failed for another reason."
  cat build_log.txt
  exit 1
done
