#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.53.1}"
VERSION="${VERSION#v}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native"
BASE_URL="https://github.com/hegeldev/hegel/releases/download/libhegel/${VERSION}"

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print tolower($1)}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print tolower($1)}'
  else
    echo "Error: neither sha256sum nor shasum is installed" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fetch_and_verify() {
  local remote_name="$1"
  local dest_path="$2"
  local write_sidecar="${3:-true}"

  local tmp_file="$TMP_DIR/$remote_name"
  local tmp_sha="$TMP_DIR/${remote_name}.sha256"

  echo "Downloading $remote_name ($VERSION)..."
  curl -fsSL "$BASE_URL/$remote_name" -o "$tmp_file"
  curl -fsSL "$BASE_URL/${remote_name}.sha256" -o "$tmp_sha"

  local expected_hash
  expected_hash="$(awk '{print tolower($1)}' "$tmp_sha" | tr -d '\r\n')"
  if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Error: invalid SHA256 format in ${remote_name}.sha256: '$expected_hash'" >&2
    exit 1
  fi

  local actual_hash
  actual_hash="$(sha256_of "$tmp_file")"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "Error: SHA256 mismatch for $remote_name" >&2
    echo "  Expected: $expected_hash" >&2
    echo "  Actual:   $actual_hash" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dest_path")"
  mv "$tmp_file" "$dest_path"
  if [[ "$dest_path" == *.dylib || "$dest_path" == *.so ]]; then
    chmod 755 "$dest_path"
  else
    chmod 644 "$dest_path"
  fi

  if [[ "$write_sidecar" == "true" ]]; then
    printf '%s\n' "$expected_hash" > "${dest_path}.sha256"
  fi

  echo "  Verified $dest_path ($expected_hash)"
}

fetch_and_verify "hegel.h" "$NATIVE_DIR/include/hegel.h" "false"
fetch_and_verify "libhegel-darwin-arm64.dylib" "$NATIVE_DIR/macos_arm64/libhegel.dylib" "true"
fetch_and_verify "libhegel-linux-amd64.so" "$NATIVE_DIR/linux_x64/libhegel.so" "true"
fetch_and_verify "libhegel-linux-arm64.so" "$NATIVE_DIR/linux_arm64/libhegel.so" "true"
fetch_and_verify "libhegel-windows-amd64.dll" "$NATIVE_DIR/windows_x64/libhegel.dll" "true"
fetch_and_verify "libhegel-windows-arm64.dll" "$NATIVE_DIR/windows_arm64/libhegel.dll" "true"

# Remove legacy hegel-rust artifacts
rm -f \
  "$NATIVE_DIR/.hegel-rust-version" \
  "$NATIVE_DIR/macos_arm64/libhegel_c.dylib" \
  "$NATIVE_DIR/macos_arm64/libhegel_c.dylib.sha256" \
  "$NATIVE_DIR/linux_x64/libhegel_c.so" \
  "$NATIVE_DIR/linux_x64/libhegel_c.so.sha256" \
  "$NATIVE_DIR/linux_arm64/libhegel_c.so" \
  "$NATIVE_DIR/linux_arm64/libhegel_c.so.sha256" \
  "$NATIVE_DIR/windows_x64/hegel_c.dll" \
  "$NATIVE_DIR/windows_x64/hegel_c.dll.sha256" \
  "$NATIVE_DIR/windows_arm64/hegel_c.dll" \
  "$NATIVE_DIR/windows_arm64/hegel_c.dll.sha256"

printf '%s\n' "$VERSION" > "$NATIVE_DIR/.libhegel-version"
echo "Done: libhegel $VERSION installed into $NATIVE_DIR"
