#!/usr/bin/env bash
set -euo pipefail

# Downloads Windsurf (now Devin) for Linux from the official apt repository
# and extracts the binary for use in the Docker container.

DEB_URL="https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt/pool/main/d/devin-desktop/Devin-linux-x64-3.0.12.deb"
DOWNLOAD_DIR="$HOME/windsurf-linux"
TEMP_DIR="/tmp/devin-extract-$$"

echo "=== Downloading Windsurf (Devin) for Linux ==="
echo "URL: $DEB_URL"
echo ""

mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$TEMP_DIR"

cd "$TEMP_DIR"

# Download the .deb
echo "[1/4] Downloading .deb package..."
curl -fsSL -o devin.deb "$DEB_URL"

echo "[2/4] Extracting package..."
# macOS doesn't have dpkg-deb, use ar + tar instead
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x devin.deb extracted/
else
    # .deb is an ar archive containing control.tar.xz and data.tar.xz
    ar -x devin.deb
    mkdir -p extracted
    # Extract data.tar.* (could be .xz, .gz, or .zst)
    for f in data.tar.*; do
        if [[ -f "$f" ]]; then
            if command -v tar >/dev/null 2>&1; then
                tar -xf "$f" -C extracted/
            else
                echo "ERROR: No tar command available"
                exit 1
            fi
            break
        fi
    done
fi

# Find the main binary
BINARY_PATH=$(find extracted -name "devin" -type f | head -1)
if [[ -z "$BINARY_PATH" ]]; then
    echo "ERROR: Could not find the devin binary in the package."
    echo "Contents of extracted package:"
    find extracted -type f | head -20
    exit 1
fi

echo "[3/4] Found binary at: $BINARY_PATH"

# Copy to destination
cp "$BINARY_PATH" "$DOWNLOAD_DIR/windsurf"
chmod +x "$DOWNLOAD_DIR/windsurf"

echo "[4/4] Binary installed to: $DOWNLOAD_DIR/windsurf"
ls -la "$DOWNLOAD_DIR/windsurf"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "=== Done ==="
echo "The Windsurf IDE binary is now available at: $DOWNLOAD_DIR/windsurf"
echo ""
echo "Next steps:"
echo "  1. Ensure docker-compose.yml has the volume mount:"
echo "       volumes:"
echo "         - ~/windsurf-linux/windsurf:/opt/windsurf/windsurf:ro"
echo "  2. Run: docker-compose up --build"
