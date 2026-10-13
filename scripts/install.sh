#!/usr/bin/env bash
# Builds a Release archive of Breeze and installs it as /Applications/Breeze.app, replacing any
# earlier copy. Run it again to update. Needs your own signing team set in Xcode; never use sudo.
#
# Usage: scripts/install.sh
#   BREEZE_INSTALL_DIR   install into this directory instead of /Applications
set -euo pipefail

readonly app_name="Breeze.app"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly install_dir="${BREEZE_INSTALL_DIR:-/Applications}"
readonly dest_app="$install_dir/$app_name"
# Spotlight skips folders named *.noindex, so the archived copy doesn't show up next to the
# installed app in Spotlight, Launchpad or Raycast.
readonly archive_path="$repo_root/build/archive.noindex/Breeze.xcarchive"
readonly archive_log="$repo_root/build/archive.log"
readonly built_app="$archive_path/Products/Applications/$app_name"

die() {
    echo "install.sh: error: $*" >&2
    exit 1
}

(($# == 0)) || die "takes no arguments (usage: scripts/install.sh)"
[[ $EUID -ne 0 ]] || die "don't run this with sudo; /Applications is writable by an admin user"
[[ -d "$install_dir" && -w "$install_dir" ]] || die "'$install_dir' is not a writable directory"

# Gotcha: `[[ -n "$(cmd)" ]]` ignores cmd's exit status, so a failing lsappinfo would read as "not
# running". `lsappinfo find` exits 0 with empty output when nothing matches.
breeze_is_running() {
    local asns
    asns="$(lsappinfo find "bundleid=$bundle_id")" ||
        die "couldn't ask LaunchServices whether Breeze is running"
    [[ -n "$asns" ]]
}

# Waits up to $1 seconds for every Breeze process to exit.
wait_for_breeze_to_exit() {
    local attempts=$(($1 * 4))
    while breeze_is_running && ((attempts > 0)); do
        sleep 0.25
        attempts=$((attempts - 1))
    done
    ! breeze_is_running
}

quit_breeze() {
    breeze_is_running || return 0
    echo "==> Quitting the running Breeze"
    # Ask nicely first. Only sent while Breeze runs: telling a stopped app to quit launches it.
    if ! osascript -e "tell application id \"$bundle_id\" to quit"; then
        echo "install.sh: warning: asking Breeze to quit failed; will terminate it" >&2
    fi
    wait_for_breeze_to_exit 10 && return 0

    echo "install.sh: warning: Breeze is still running; sending SIGTERM" >&2
    pkill -x Breeze || true # it may have exited between the check and pkill
    wait_for_breeze_to_exit 5 || die "Breeze is still running; quit it and run this again"
}

# 1. Build and check.
echo "==> Building a Release archive (log: build/archive.log)"
mkdir -p "$repo_root/build"
rm -rf "$archive_path"
if ! xcodebuild \
    -project "$repo_root/Breeze.xcodeproj" \
    -scheme Breeze \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    archive -archivePath "$archive_path" >"$archive_log" 2>&1; then
    tail -n 30 "$archive_log" >&2
    die "the Release archive failed; full log in $archive_log"
fi
[[ -d "$built_app" ]] || die "the archive has no $app_name at $built_app"
# Read from the build, so a fork with its own bundle identifier quits the right app.
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")"
readonly bundle_id

# 2. Copy next to the destination first, so a failed or interrupted copy never touches the
#    installed app. The staging directory is on the same volume, so the moves below are renames.
staging_dir="$(mktemp -d "$install_dir/.breeze-install.XXXXXX")" ||
    die "couldn't create a staging directory in $install_dir"
readonly staging_dir
readonly staged_app="$staging_dir/$app_name"
readonly previous_app="$staging_dir/previous-$app_name"

# Runs on every exit, including Ctrl-C: if the old app was moved aside but the new one never
# made it into place, put the old one back before deleting the staging directory.
cleanup() {
    if [[ -e "$previous_app" && ! -e "$dest_app" ]]; then
        if ! mv "$previous_app" "$dest_app"; then
            echo "install.sh: error: couldn't restore the old app; it is at $previous_app" >&2
            return
        fi
        echo "install.sh: restored the old app at $dest_app" >&2
    fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT

echo "==> Copying to $install_dir"
ditto "$built_app" "$staged_app" || die "copying the app into $install_dir failed"
echo "==> Verifying the code signature"
codesign --verify --strict "$staged_app" || die "code signature check failed for $staged_app"

# 3. Swap: move the old copy aside, then the new one in (`cleanup` puts the old one back if the
#    second move fails). The old copy is deleted with the staging directory.
quit_breeze

if [[ -e "$dest_app" ]]; then
    mv "$dest_app" "$previous_app" || die "couldn't move the old $dest_app aside"
fi
mv "$staged_app" "$dest_app" || die "couldn't move the new app into place at $dest_app"

# 4. Report and launch.
plist="$dest_app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
echo "==> Installed Breeze $version ($build) at $dest_app"
open "$dest_app" || die "installed, but launching $dest_app failed"
