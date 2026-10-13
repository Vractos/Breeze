# Breeze

A small native macOS menu bar app for controlling an LG air conditioner through LG's official
[ThinQ Connect API](https://smartsolution.developer.lge.com/en/apiManage/thinq_connect).

From the menu bar you can:

- turn the AC on and off
- change the mode and the target temperature
- set the fan to Auto or a specific level
- toggle up/down swing and the display light
- set or cancel a sleep timer
- switch between several ACs on the same account

Settings also shows the selected AC's energy usage, with an optional cost estimate if you enter
a price per kWh.

## Requirements

- macOS 27
- Xcode 27
- An LG ThinQ account with your AC already added in the LG ThinQ app
- A ThinQ Connect personal access token, created at <https://connect-pat.lgthinq.com>

## Build and run

1. Open `Breeze.xcodeproj` in Xcode.
2. Under the Breeze target's *Signing & Capabilities*, choose your own team (you may also need
   to change the bundle identifier).
3. Press ⌘R.
4. Click the Breeze icon in the menu bar, open Settings → Account, paste your token and pick
   your account's country. The token is stored in the macOS Keychain.

Run the tests with ⌘U in Xcode, or for the API package alone:

```sh
cd Packages/ThinQKit
swift test
```

## Install

To use Breeze as a normal app (Spotlight, Launchpad, launch at login) rather than a build that
Xcode runs:

1. Choose your own signing team first (step 2 above). A free Personal Team is enough.
2. Run:

   ```sh
   scripts/install.sh
   ```

   It builds a Release archive into `build/`, checks the code signature, quits Breeze if it is
   running, installs the app as `/Applications/Breeze.app` (the old copy is replaced only once
   the new one is fully copied), opens it and prints the version. No `sudo` needed.
3. Run it again after pulling changes to update.

To install somewhere other than `/Applications`, set `BREEZE_INSTALL_DIR=<dir>`.

The installed app and a copy you run from Xcode share the same bundle identifier, settings and
Keychain item. Quit the installed Breeze before pressing ⌘R, or you get two menu bar icons. If
launch at login is on, the copy in `/Applications` takes the login item over the next time it
starts.

## The `thinq` command-line tool

`Packages/ThinQKit` also builds `thinq`, a small CLI on top of the same library. It is handy for
looking at what your AC reports and for trying commands.

```sh
cd Packages/ThinQKit
export THINQ_PAT='<your token>'
export THINQ_COUNTRY=US          # your ThinQ account's country (defaults to BR)

swift run thinq devices          # list devices: id, type, model, alias
swift run thinq profile <deviceId> [--raw]
swift run thinq state <deviceId> [--raw]
swift run thinq set <deviceId> power on
swift run thinq set <deviceId> temp 22.5
swift run thinq set <deviceId> fan AUTO
swift run thinq help             # every command
```

The token is read only from the `THINQ_PAT` environment variable, never from a command-line
flag, so it stays out of your shell history.

## Project layout

| Path | What it is |
|---|---|
| `Breeze/` | The SwiftUI app: menu bar panel, Settings window, the store that polls and sends commands, Keychain and login-item services |
| `Packages/ThinQKit/` | Swift package with the ThinQ Connect client and air-conditioner model (no UI code), plus the `thinq` CLI and its tests |
| `BreezeTests/` | Tests for the app |
| `scripts/install.sh` | Builds and installs the app into `/Applications` |

## Privacy

- Your token is kept only in the macOS Keychain (app) or in the `THINQ_PAT` environment
  variable (CLI). It is never logged.
- Breeze talks only to LG's ThinQ Connect API. There is no analytics, telemetry or other server.
- Local device nicknames and the optional energy price stay on your Mac.

## Disclaimer

Breeze is an unofficial personal project. It is not affiliated with, endorsed by or supported
by LG Electronics. "LG" and "ThinQ" are trademarks of LG Electronics.
