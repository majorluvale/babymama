#!/usr/bin/env bash
# Generates the native platform folders (android/, ios/, web/) of the three Flutter apps,
# adds the permissions they need, then runs `flutter pub get`.
# Run once after cloning, from Git Bash (Windows), macOS or Linux:   bash scripts/setup_flutter.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ORG=ke.babymama

create() { # dir project_name platforms
  local dir=$1 name=$2 platforms=$3
  echo "==> $dir ($platforms)"
  (cd "apps/$dir" && flutter create --org "$ORG" --project-name "$name" --platforms="$platforms" . >/dev/null)
  # flutter create adds a sample test referencing a MyApp class that does not exist here.
  rm -f "apps/$dir/test/widget_test.dart"
}

android_permission() { # dir permission
  local manifest="apps/$1/android/app/src/main/AndroidManifest.xml"
  [ -f "$manifest" ] || return 0
  grep -q "$2" "$manifest" || perl -0pi -e "s#<application#<uses-permission android:name=\"$2\"/>\n    <application#" "$manifest"
}

ios_plist() { # dir key description
  local plist="apps/$1/ios/Runner/Info.plist"
  [ -f "$plist" ] || return 0
  grep -q "<key>$2</key>" "$plist" && return 0
  # Insert before the last </dict>
  awk -v key="$2" -v val="$3" '
    { lines[NR] = $0 }
    /<\/dict>/ { last = NR }
    END { for (i = 1; i <= NR; i++) { if (i == last) { print "\t<key>" key "</key>"; print "\t<string>" val "</string>" } print lines[i] } }
  ' "$plist" > "$plist.tmp" && mv "$plist.tmp" "$plist"
}

create customer_app babymama android,ios,web
create driver_app babymama_rider android,ios
create admin_app babymama_admin web

for app in customer_app driver_app; do
  android_permission $app android.permission.INTERNET
done
android_permission driver_app android.permission.ACCESS_FINE_LOCATION
android_permission driver_app android.permission.ACCESS_COARSE_LOCATION

ios_plist customer_app NSPhotoLibraryUsageDescription "Babymama needs your photos to list the clothes you sell."
ios_plist customer_app NSCameraUsageDescription "Babymama uses the camera to photograph the clothes you sell."
ios_plist driver_app NSLocationWhenInUseUsageDescription "Babymama Rider shares your position with customers while you deliver."

(cd packages/babymama_core && flutter pub get)
for app in customer_app driver_app admin_app; do (cd "apps/$app" && flutter pub get); done

echo
echo "Done. Next steps:"
echo "  - Google Sign-In: see README section 'Connexion Google' (Android SHA-1, iOS URL scheme)."
echo "  - Run: cd apps/customer_app && flutter run -d chrome --dart-define=API_URL=http://localhost:4000"
