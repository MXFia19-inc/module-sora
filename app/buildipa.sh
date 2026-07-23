#!/bin/bash

# Build d'un IPA non signé (sideload). Calqué sur TwitchUnblock/buildipa.sh,
# lui-même inspiré de https://github.com/cranci1/Sora/blob/dev/ipabuild.sh

set -e

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=ModuleTester
SCHEME_NAME="ModuleTester"

# Génère le .xcodeproj depuis project.yml si absent (nécessite xcodegen)
if [ ! -d "$APPLICATION_NAME.xcodeproj" ]; then
  echo "--- Generating Xcode project with XcodeGen ---"
  xcodegen generate --spec project.yml
fi

if [ ! -d "build" ]; then
  mkdir build
fi

cd build

echo "--- Building $APPLICATION_NAME for iOS ---"

xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -derivedDataPath "$WORKING_LOCATION/build/DerivedDataApp" \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  clean build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO"

DD_APP_PATH="$WORKING_LOCATION/build/DerivedDataApp/Build/Products/Release-iphoneos/$APPLICATION_NAME.app"
TARGET_APP="$WORKING_LOCATION/build/$APPLICATION_NAME.app"

if [ ! -d "$DD_APP_PATH" ]; then
  echo "Error: Build failed, .app not found at $DD_APP_PATH"
  exit 1
fi

cp -r "$DD_APP_PATH" "$TARGET_APP"

echo "--- Removing code signature ---"
codesign --remove "$TARGET_APP" || true
if [ -e "$TARGET_APP/_CodeSignature" ]; then
  rm -rf "$TARGET_APP/_CodeSignature"
fi
if [ -e "$TARGET_APP/embedded.mobileprovision" ]; then
  rm -rf "$TARGET_APP/embedded.mobileprovision"
fi

echo "--- Packaging IPA ---"
mkdir Payload
cp -r "$APPLICATION_NAME.app" "Payload/$APPLICATION_NAME.app"
strip "Payload/$APPLICATION_NAME.app/$APPLICATION_NAME" || true
zip -vr "$APPLICATION_NAME.ipa" Payload

rm -rf "$APPLICATION_NAME.app"
rm -rf Payload

echo "--- Success: build/$APPLICATION_NAME.ipa created ---"
