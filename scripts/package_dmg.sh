#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/.derivedData/Build/Products/Release/GitCalendar.app}"
version="${2:-1.0.0}"
output_dir="${3:-$project_root/dist}"
signing_identity="${4:-}"

if [[ ! -d "$app_path" ]]; then
  print -u2 "Приложение не найдено: $app_path"
  exit 1
fi

staging_dir="$(mktemp -d -t git-calendar-dmg)"
case "$staging_dir" in
  /private/var/folders/*|/var/folders/*|/tmp/*) ;;
  *)
    print -u2 "Небезопасный временный путь: $staging_dir"
    exit 1
    ;;
esac
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$output_dir"
ditto "$app_path" "$staging_dir/Git Calendar.app"
ln -s /Applications "$staging_dir/Applications"

widget_path="$staging_dir/Git Calendar.app/Contents/PlugIns/GitCalendarWidget.appex"
staged_app="$staging_dir/Git Calendar.app"

if [[ -z "$signing_identity" ]] && ! codesign --verify --deep --strict "$staged_app" 2>/dev/null; then
  signing_identity="-"
fi

if [[ -n "$signing_identity" ]]; then
  app_group="$(/usr/libexec/PlistBuddy -c 'Print :AppGroupIdentifier' "$staged_app/Contents/Info.plist")"
  if [[ -z "$app_group" || "$app_group" == *'$('* ]]; then
    print -u2 "Не удалось определить App Group из собранного приложения"
    exit 1
  fi

  app_entitlements="$staging_dir/app.entitlements"
  widget_entitlements="$staging_dir/widget.entitlements"
  cp "$project_root/GitCalendarApp/GitCalendar.entitlements" "$app_entitlements"
  cp "$project_root/GitCalendarWidget/GitCalendarWidget.entitlements" "$widget_entitlements"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $app_group" "$app_entitlements"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $app_group" "$widget_entitlements"

  if [[ -d "$widget_path" ]]; then
    codesign --force --sign "$signing_identity" \
      --entitlements "$widget_entitlements" \
      "$widget_path"
  fi
  codesign --force --sign "$signing_identity" \
    --entitlements "$app_entitlements" \
    "$staged_app"
  rm -f "$app_entitlements" "$widget_entitlements"
fi
codesign --verify --deep --strict "$staged_app"

output_path="$output_dir/GitCalendar-$version.dmg"
hdiutil create \
  -volname "Git Calendar" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$output_path"

print "$output_path"
