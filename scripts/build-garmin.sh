#!/usr/bin/env bash
set -euo pipefail

developer_key="${GARMIN_DEVELOPER_KEY:-}"
device="fenix8solar47mm"
release=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --developer-key)
            developer_key="${2:-}"
            shift 2
            ;;
        --device)
            device="${2:-}"
            shift 2
            ;;
        --release)
            release=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_root/.." && pwd)"
garmin_root="$project_root/garmin"
output_root="$garmin_root/build"
connect_iq_root="$HOME/Library/Application Support/Garmin/ConnectIQ"

if [[ -z "$developer_key" && -f "$project_root/garmin-keys/developer_key.der" ]]; then
    developer_key="$project_root/garmin-keys/developer_key.der"
fi
if [[ -z "$developer_key" || ! -f "$developer_key" ]]; then
    echo "Set GARMIN_DEVELOPER_KEY or pass --developer-key with an existing developer key." >&2
    exit 1
fi

if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
    android_studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    if [[ -x "$android_studio_jbr/bin/java" ]]; then
        export JAVA_HOME="$android_studio_jbr"
    elif ! command -v java >/dev/null 2>&1 || ! java -version >/dev/null 2>&1; then
        echo "Java not found. Install a JDK or Android Studio before building the Garmin app." >&2
        exit 1
    fi
fi

current_sdk="$connect_iq_root/current-sdk.cfg"
if [[ ! -f "$current_sdk" ]]; then
    echo "Connect IQ SDK not found. Install it with Garmin Connect IQ SDK Manager." >&2
    exit 1
fi
sdk_root="$(tr -d '\r\n' < "$current_sdk")"
monkeyc="$sdk_root/bin/monkeyc"
if [[ ! -x "$monkeyc" ]]; then
    echo "Connect IQ compiler not found in the configured SDK." >&2
    exit 1
fi

mkdir -p "$output_root"
compiler_args=(-f monkey.jungle -y "$developer_key" -w)
if [[ "$release" -eq 1 ]]; then
    output="$output_root/gymapp-garmin-connect-iq.iq"
    compiler_args+=(-o "$output" -r -e)
else
    if [[ ! -d "$connect_iq_root/Devices/$device" ]]; then
        echo "Connect IQ device '$device' is not installed." >&2
        exit 1
    fi
    output="$output_root/gymapp-$device.prg"
    compiler_args+=(-o "$output" -d "$device")
fi

(
    cd "$garmin_root"
    "$monkeyc" "${compiler_args[@]}"
)
echo "Garmin build: $output"
