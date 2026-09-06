#!/bin/sh
set -eu

# Read the processed app metadata so Settings always describes this exact build.
app_info="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
settings_root="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Settings.bundle/Root.plist"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info")
app_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info")

mkdir -p "$(dirname "$settings_root")"
cp "${SRCROOT}/Tonight/Resources/Settings.bundle/Root.plist" "$settings_root"
/usr/libexec/PlistBuddy -c "Set :PreferenceSpecifiers:0:DefaultValue ${app_version} (${app_build})" "$settings_root"
