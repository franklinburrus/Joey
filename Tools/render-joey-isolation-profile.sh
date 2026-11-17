#!/usr/bin/env bash
# Render Joey's deny-by-default preview profile for one task-owned runtime.
# No production path is granted. The generated profile is disposable.
set -euo pipefail

usage() {
  echo "usage: $0 --runtime-root ABSOLUTE_PATH --atomic-temp-root ABSOLUTE_PATH --output ABSOLUTE_PATH" >&2
  exit 2
}

runtime_root=""
atomic_temp_root=""
output=""
while (($# > 0)); do
  case "$1" in
    --runtime-root)
      (($# >= 2)) || usage
      runtime_root="$2"
      shift 2
      ;;
    --atomic-temp-root)
      (($# >= 2)) || usage
      atomic_temp_root="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || usage
      output="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

host_home="${JOEY_ISOLATION_HOST_HOME:-$HOME}"

validate_path() {
  local name="$1"
  local value="$2"
  case "$value" in
    /*) ;;
    *) echo "$name must be absolute: $value" >&2; exit 2 ;;
  esac
  case "$value" in
    *$'\n'*|*'"'*) echo "$name contains an unsupported character" >&2; exit 2 ;;
  esac
}

[[ -n "$runtime_root" && -n "$atomic_temp_root" && -n "$output" ]] || usage
validate_path "--runtime-root" "$runtime_root"
validate_path "--atomic-temp-root" "$atomic_temp_root"
validate_path "--output" "$output"
validate_path "JOEY_ISOLATION_HOST_HOME" "$host_home"
[[ -d "$atomic_temp_root" ]] || { echo "--atomic-temp-root must exist: $atomic_temp_root" >&2; exit 2; }
atomic_temp_root="$(cd "$atomic_temp_root" && pwd -P)"

mkdir -p "$(dirname "$output")"

{
  printf '%s\n' '(version 1)' '(allow default)' '(deny network*)'
  # Deny every write first. Reopen only the task-owned runtime and /dev/null.
  # HOME/TMPDIR redirection alone cannot protect absolute paths such as
  # external media mounted outside the host home.
  printf '%s\n' '(deny file-write*)'
  printf '(allow file-write* (subpath "%s"))\n' "$runtime_root"
  printf '%s\n' '(allow file-write* (literal "/dev/null"))'
  # Foundation's Data.write(.atomic) stages NSIRD files in Darwin's user
  # temporary directory before renaming into the task runtime. Permit only
  # Joey's temporary-item prefix there; all other outside writes stay denied.
  printf '(allow file-write* (regex #"^%s/TemporaryItems/NSIRD_Joey_[^/]+(/.*)?$"))\n' "$atomic_temp_root"
  printf '(deny file-read* file-write* (subpath "%s/Library/Application Support/Joey Native"))\n' "$host_home"
  printf '(deny file-read* file-write* (subpath "/System/Volumes/Data%s/Library/Application Support/Joey Native"))\n' "$host_home"
  printf '(deny file-read* file-write* (subpath "%s/Library/Keychains"))\n' "$host_home"
  printf '(deny file-read* file-write* (subpath "%s/.config/rclone"))\n' "$host_home"
  printf '(deny file-read* file-write* (subpath "%s/Library/CloudStorage"))\n' "$host_home"
  printf '%s\n' '(deny mach-lookup (global-name "com.apple.securityd") (global-name "com.apple.secd") (global-name "com.apple.securityd.xpc"))'
  printf '%s\n' '(deny mach-lookup (global-name "com.apple.cfprefsd.agent") (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.SecurityServer"))'
} > "$output"

chmod 600 "$output"
shasum -a 256 "$output"
