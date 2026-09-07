#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/.derivedData/Build/Products/Release/GitCalendar.app}"
version="${2:-1.0.0}"
output_dir="${3:-$project_root/dist}"

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
if [[ -d "$widget_path" ]]; then
  codesign --force --sign - \
    --entitlements "$project_root/GitCalendarWidget/GitCalendarWidget.entitlements" \
    "$widget_path"
fi
codesign --force --sign - \
  --entitlements "$project_root/GitCalendarApp/GitCalendar.entitlements" \
  "$staging_dir/Git Calendar.app"
codesign --verify --deep --strict "$staging_dir/Git Calendar.app"

output_path="$output_dir/GitCalendar-$version.dmg"
hdiutil create \
  -volname "Git Calendar" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$output_path"

print "$output_path"
