#!/bin/sh
set -eu

# 개발용 빌드와 시뮬레이터의 심볼은 업로드하지 않는다.
if [ "${CONFIGURATION}" != "Release" ] || [ "${PLATFORM_NAME}" != "iphoneos" ]; then
  exit 0
fi

# Flutter의 SPM 빌드와 Xcode의 DerivedData 경로를 모두 지원한다.
upload_symbols="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
if [ ! -x "$upload_symbols" ]; then
  echo "error: Firebase Crashlytics upload-symbols was not found: $upload_symbols" >&2
  exit 1
fi

# lib/firebase_options.dart에 설정된 iOS Firebase 앱 ID를 사용한다.
firebase_app_id='1:979415511220:ios:89c489f71a92ea095d67e1'
for dsym in "${DWARF_DSYM_FILE_NAME}" App.framework.dSYM; do
  if [ ! -d "${DWARF_DSYM_FOLDER_PATH}/$dsym" ]; then
    echo "error: Required dSYM was not found: ${DWARF_DSYM_FOLDER_PATH}/$dsym" >&2
    exit 1
  fi
done

# 업로드 실패를 빌드에 표시하도록 완료까지 기다린다.
"$upload_symbols" -ai "$firebase_app_id" -p ios -- "${DWARF_DSYM_FOLDER_PATH}"
