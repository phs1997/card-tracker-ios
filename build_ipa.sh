#!/usr/bin/env bash
set -euo pipefail

# Build script for Card Tracker (iOS)
# Produces an unsigned .ipa suitable for Sideloadly or distribution.

SCHEME="Pokemon Tracker"
PROJECT="Pokemon Tracker.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="./build"
ARCHIVE_PATH="${BUILD_DIR}/PokemonTracker.xcarchive"
IPA_DIR="${BUILD_DIR}/IPA"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
OUTPUT_IPA="${IPA_DIR}/CardTracker.ipa"

echo "=== 1. Cleaning build directory ==="
rm -rf "${BUILD_DIR}"
mkdir -p "${IPA_DIR}" "${PAYLOAD_DIR}"

echo "=== 2. Creating Xcode Archive ==="
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=iOS" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

echo "=== 3. Packaging .ipa ==="
APP_BUNDLE=$(find "${ARCHIVE_PATH}/Products/Applications" -name "*.app" -maxdepth 1 | head -n 1)

if [ -z "${APP_BUNDLE}" ]; then
    echo "Error: App bundle not found in archive."
    exit 1
fi

cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/"
cd "${BUILD_DIR}"
zip -qr "${IPA_DIR}/CardTracker.ipa" Payload
cd - > /dev/null

echo "=== Build Complete ==="
echo "IPA created at: ${OUTPUT_IPA}"
