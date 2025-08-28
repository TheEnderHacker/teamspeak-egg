#!/bin/bash
set -euo pipefail

echo "=== TeamSpeak Update/Start Script ==="

# --- Installed version
INSTALLED_VERSION="$( [ -s version_installed.txt ] && cat version_installed.txt || echo "" )"
echo "Installed TeamSpeak3 Version: ${INSTALLED_VERSION:-<none>}"

# --- Latest version (2 Mirrors)
read_latest() {
  for URL in \
    "https://raw.githubusercontent.com/jpylypiw/teamspeak-egg/master/tsversion" \
    "https://raw.githubusercontent.com/KingJP/teamspeak-egg/master/tsversion"
  do
    if LATEST_VERSION="$(curl -fsSL "$URL" 2>/dev/null | tr -d '\r' | head -n1)"; then
      [ -n "$LATEST_VERSION" ] && { echo "$LATEST_VERSION"; return 0; }
    fi
  done
  return 1
}
LATEST_VERSION="$(read_latest || true)"
echo "Latest TeamSpeak3 Version: ${LATEST_VERSION:-<unknown>}"

# --- Static version from version_static.txt
STATIC_VERSION=""
if [ -f version_static.txt ]; then
  if grep -q '=' version_static.txt; then
    # shellcheck disable=SC1091
    . ./version_static.txt || true
    STATIC_VERSION="${SERVER_VERSION:-}"
  else
    STATIC_VERSION="$(tr -d '\r' < version_static.txt)"
  fi
fi
if [ -n "${STATIC_VERSION:-}" ] && [ "${STATIC_VERSION}" != "undefined" ] && [ "${STATIC_VERSION}" != "0" ]; then
  echo "Server is set to static version: $STATIC_VERSION"
  TARGET_VERSION="$STATIC_VERSION"
else
  TARGET_VERSION="$LATEST_VERSION"
fi

# --- Download + extract
download_and_extract() {
  local v="$1"
  echo "Cleaning up old files..."
  rm -rf doc redist serverquerydocs sql tsdns CHANGELOG LICENSE* *.so ts3server || true

  echo "Downloading TeamSpeak $v..."
  local URL_AMD64="https://files.teamspeak-services.com/releases/server/${v}/teamspeak3-server_linux_amd64-${v}.tar.bz2"
  local URL_ALPINE="https://files.teamspeak-services.com/releases/server/${v}/teamspeak3-server_linux_alpine-${v}.tar.bz2"

  if curl -fsI "$URL_AMD64" >/dev/null 2>&1; then
    curl -fsSL "$URL_AMD64" | tar xj --strip-components=1
  elif curl -fsI "$URL_ALPINE" >/dev/null 2>&1; then
    curl -fsSL "$URL_ALPINE" | tar xj --strip-components=1
  else
    echo "ERROR: Could not download TeamSpeak version $v" >&2
    exit 1
  fi

  echo "Setting permissions..."
  chmod +x ts3server_minimal_runscript.sh ts3server_startscript.sh || true
  [ -f ts3server ] && chmod +x ts3server || true

  : > .ts3server_license_accepted
  echo "$v" > version_installed.txt
  echo "Updated version_installed.txt = $v"
}

# --- Check update
if [ ! -f ts3server ] || [ -z "${INSTALLED_VERSION}" ] || [ "$TARGET_VERSION" != "$INSTALLED_VERSION" ]; then
  download_and_extract "$TARGET_VERSION"
else
  echo "No update required."
fi

# --- Create ini if missing
if [ ! -f ts3server.ini ] || [ ! -s ts3server.ini ]; then
  echo "Creating ts3server.ini..."
  ./ts3server_startscript.sh start createinifile=1 || true
  sleep 2
  pgrep ts3server >/dev/null 2>&1 && kill "$(pgrep ts3server)" || true
fi

mkdir -p logs || true
echo "Starting server..."
exec ./ts3server_minimal_runscript.sh inifile=ts3server.ini
