#!/usr/bin/env bash
set -euo pipefail

readonly trusted_release_public_key_sha256="926b106c47125ddc97aef9801ffd4812f54562140122bb30f792493ed92adb47"

developer_key="${GARMIN_DEVELOPER_KEY:-}"
requested_release_public_key_sha256="${GARMIN_RELEASE_PUBLIC_KEY_SHA256:-}"
device="fenix8solar47mm"
mode="compile-only"
mode_was_explicit=0

require_argument_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Argument '$1' requires a value." >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --developer-key)
            require_argument_value "$@"
            developer_key="$2"
            shift 2
            ;;
        --device)
            require_argument_value "$@"
            device="$2"
            shift 2
            ;;
        --expected-public-key-sha256)
            require_argument_value "$@"
            requested_release_public_key_sha256="$2"
            shift 2
            ;;
        --release)
            if [[ "$mode_was_explicit" -eq 1 ]]; then
                echo "Choose exactly one mode: --release or --compile-only." >&2
                exit 2
            fi
            mode="release"
            mode_was_explicit=1
            shift
            ;;
        --compile-only)
            if [[ "$mode_was_explicit" -eq 1 ]]; then
                echo "Choose exactly one mode: --release or --compile-only." >&2
                exit 2
            fi
            mode="compile-only"
            mode_was_explicit=1
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
java_command="${JAVA_HOME:+$JAVA_HOME/bin/java}"
if [[ -z "$java_command" || ! -x "$java_command" ]]; then
    java_command="$(command -v java)"
fi
if [[ "$(uname -s)" == "Darwin" &&
      " ${JAVA_TOOL_OPTIONS:-} " != *" -Djava.awt.headless="* ]]; then
    export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Djava.awt.headless=true"
fi

current_sdk="$connect_iq_root/current-sdk.cfg"
if [[ ! -f "$current_sdk" ]]; then
    echo "Connect IQ SDK not found. Install it with Garmin Connect IQ SDK Manager." >&2
    exit 1
fi
sdk_root="$(tr -d '\r\n' < "$current_sdk")"
monkeyc="$sdk_root/bin/monkeyc"
monkeybrains="$sdk_root/bin/monkeybrains.jar"
if [[ ! -x "$monkeyc" ]]; then
    echo "Connect IQ compiler not found in the configured SDK." >&2
    exit 1
fi
if [[ "$mode" == "release" && ! -f "$monkeybrains" ]]; then
    echo "Connect IQ SDK package reader not found; release readback cannot run." >&2
    exit 1
fi

temporary_output=""
sanitized_release_output=""
temporary_settings=""
temporary_debug=""
release_validation_root=""
release_staging_root=""
cleanup() {
    if [[ -n "$temporary_output" && -f "$temporary_output" ]]; then
        rm -f -- "$temporary_output"
    fi
    if [[ -n "$sanitized_release_output" && -f "$sanitized_release_output" ]]; then
        rm -f -- "$sanitized_release_output"
    fi
    if [[ -n "$release_validation_root" && -d "$release_validation_root" ]]; then
        rm -rf -- "$release_validation_root"
    fi
    if [[ -n "$release_staging_root" && -d "$release_staging_root" ]]; then
        rm -rf -- "$release_staging_root"
    fi
    if [[ -n "$temporary_settings" && -f "$temporary_settings" ]]; then
        rm -f -- "$temporary_settings"
    fi
    if [[ -n "$temporary_debug" && -f "$temporary_debug" ]]; then
        rm -f -- "$temporary_debug"
    fi
}
trap cleanup EXIT

normalize_sha256() {
    local normalized
    normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]:')"
    if [[ ! "$normalized" =~ ^[0-9a-f]{64}$ ]]; then
        return 1
    fi
    printf '%s' "$normalized"
}

if [[ "$mode" == "release" ]]; then
    local_fingerprint_file="$project_root/garmin-keys/release_public_key.sha256"
    if [[ -z "$requested_release_public_key_sha256" && -f "$local_fingerprint_file" ]]; then
        if [[ "$(wc -c < "$local_fingerprint_file")" -gt 256 ]]; then
            echo "Local Garmin release fingerprint file is malformed." >&2
            exit 1
        fi
        requested_release_public_key_sha256="$(<"$local_fingerprint_file")"
    fi
    expected_release_public_key_sha256="$trusted_release_public_key_sha256"
    if [[ -n "$requested_release_public_key_sha256" ]]; then
        if ! expected_release_public_key_sha256="$(normalize_sha256 "$requested_release_public_key_sha256")"; then
            echo "Expected Garmin release public-key SHA-256 must contain exactly 64 hexadecimal digits." >&2
            exit 1
        fi
    fi
    if [[ "$expected_release_public_key_sha256" != "$trusted_release_public_key_sha256" ]]; then
        echo "Expected Garmin release signer does not match the pinned Store identity." >&2
        exit 1
    fi

    openssl_command="$(command -v openssl || true)"
    if [[ -z "$openssl_command" ]]; then
        echo "OpenSSL is required to validate the Garmin release developer key." >&2
        exit 1
    fi
    umask 077
    release_validation_root="$(mktemp -d "${TMPDIR:-/tmp}/gymapp-garmin-key.XXXXXX")"
    public_key_der="$release_validation_root/public-key.der"
    if ! "$openssl_command" pkey -in "$developer_key" -inform DER \
            -pubout -outform DER -out "$public_key_der" 2>/dev/null; then
        echo "Garmin release developer key must be a valid DER private key." >&2
        exit 1
    fi
    public_key_description="$(
        "$openssl_command" pkey -pubin -inform DER -in "$public_key_der" \
            -text -noout 2>/dev/null
    )"
    if ! grep -Eq '(RSA )?Public-Key: \(4096 bit' <<<"$public_key_description"; then
        echo "Garmin release developer key must use RSA-4096." >&2
        exit 1
    fi
    actual_release_public_key_sha256="$(
        "$openssl_command" dgst -sha256 "$public_key_der" | awk '{print tolower($NF)}'
    )"
    if [[ ! "$actual_release_public_key_sha256" =~ ^[0-9a-f]{64}$ ||
          "$actual_release_public_key_sha256" != "$expected_release_public_key_sha256" ]]; then
        echo "Garmin release developer key does not match the trusted public-key fingerprint." >&2
        exit 1
    fi
fi

mkdir -p "$output_root"
compiler_args=(-f monkey.jungle -y "$developer_key" -w)
if [[ "$mode" == "release" ]]; then
    output="$output_root/gymapp-garmin-connect-iq.iq"
    if ! release_staging_root="$(
        mktemp -d "$output_root/.gymapp-garmin-release.XXXXXX" 2>/dev/null
    )"; then
        echo "Garmin release staging directory could not be created." >&2
        exit 1
    fi
    raw_release_root="$release_staging_root/raw"
    sanitized_release_root="$release_staging_root/sanitized"
    if ! mkdir -p -- "$raw_release_root" "$sanitized_release_root" 2>/dev/null; then
        echo "Garmin release staging directories could not be prepared." >&2
        exit 1
    fi
    # monkeyc derives every internal PRG filename from the -o leaf name. Keep
    # that leaf canonical while isolating raw and sanitized packages by folder.
    temporary_output="$raw_release_root/gymapp-garmin-connect-iq.iq"
    sanitized_release_output="$sanitized_release_root/gymapp-garmin-connect-iq.iq"
    compiler_args+=(-o "$temporary_output" -r -e)
else
    if [[ ! -d "$connect_iq_root/Devices/$device" ]]; then
        echo "Connect IQ device '$device' is not installed." >&2
        exit 1
    fi
    output="$output_root/gymapp-$device.prg"
    temporary_output="$output_root/.gymapp-$device.$$.prg"
    temporary_settings="${temporary_output%.prg}-settings.json"
    temporary_debug="$temporary_output.debug.xml"
    rm -f -- "$temporary_output" "$temporary_settings" "$temporary_debug"
    compiler_args+=(-o "$temporary_output" -d "$device")
    # CIQ 3.4 watch apps on these products have a 96 KiB ceiling. The SDK 9.2
    # debug table alone pushes the otherwise-valid compact build over that cap;
    # strip only debug metadata while retaining identical runtime code.
    case "$device" in
        descentg1|instinct2|instinct2s|instinct2x|instinctcrossover)
            compiler_args+=(-r)
            ;;
    esac
fi

if [[ "$mode" == "release" ]]; then
    if ! (
        cd "$garmin_root"
        "$monkeyc" "${compiler_args[@]}" >/dev/null 2>&1
    ); then
        echo "Garmin release compilation failed." >&2
        exit 1
    fi
else
    (
        cd "$garmin_root"
        "$monkeyc" "${compiler_args[@]}"
    )
fi
if [[ ! -s "$temporary_output" ]]; then
    echo "Garmin compiler did not produce a non-empty output." >&2
    exit 1
fi
if [[ "$mode" == "release" ]]; then
    if ! "$java_command" -cp "$monkeybrains" \
            "$project_root/scripts/VerifyGarminIq.java" \
            --sanitize-debug-paths "$temporary_output" "$sanitized_release_output" \
            "$project_root" \
            >/dev/null 2>&1; then
        echo "Garmin IQ debug-path sanitization failed." >&2
        exit 1
    fi
    if [[ ! -s "$sanitized_release_output" ]]; then
        echo "Garmin IQ sanitization did not produce a non-empty output." >&2
        exit 1
    fi
    if ! "$java_command" -cp "$monkeybrains" \
            "$project_root/scripts/VerifyGarminIq.java" "$sanitized_release_output" \
            >/dev/null 2>&1; then
        echo "Garmin IQ structural/signature readback failed." >&2
        exit 1
    fi
    mv -f -- "$sanitized_release_output" "$output"
    sanitized_release_output=""
else
    if [[ -f "$temporary_settings" ]]; then
        mv -f -- "$temporary_settings" "${output%.prg}-settings.json"
        temporary_settings=""
    fi
    if [[ -f "$temporary_debug" ]]; then
        mv -f -- "$temporary_debug" "$output.debug.xml"
        temporary_debug=""
    fi
    mv -f -- "$temporary_output" "$output"
    temporary_output=""
fi
if [[ "$mode" == "release" ]]; then
    echo "Garmin build: garmin/build/gymapp-garmin-connect-iq.iq"
else
    echo "Garmin build: $output"
fi
