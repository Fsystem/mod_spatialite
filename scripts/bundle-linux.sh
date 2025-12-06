#!/bin/bash
set -e

# Bundle mod_spatialite and all its dependencies for Linux
# Usage: ./bundle-linux.sh [x64|arm64]

ARCH="${1:-x64}"
OUTPUT_DIR="output"

echo "=== Bundling mod_spatialite for Linux $ARCH ==="

# Determine library path based on architecture
if [ "$ARCH" = "arm64" ]; then
    LIB_PATH="/usr/lib/aarch64-linux-gnu"
else
    LIB_PATH="/usr/lib/x86_64-linux-gnu"
fi

# Find mod_spatialite
MOD_SPATIALITE="$LIB_PATH/mod_spatialite.so"

# Also check common alternative locations
if [ ! -f "$MOD_SPATIALITE" ]; then
    MOD_SPATIALITE="/usr/lib/mod_spatialite.so"
fi

if [ ! -f "$MOD_SPATIALITE" ]; then
    echo "Error: mod_spatialite.so not found"
    echo "Install with: sudo apt-get install libsqlite3-mod-spatialite"
    exit 1
fi

echo "Found mod_spatialite at: $MOD_SPATIALITE"

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Function to get all shared library dependencies
get_deps() {
    local lib="$1"
    ldd "$lib" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$" | sort -u || true
}

# Libraries to skip (system libraries that should always be present)
# NOTE: We do NOT skip libsqlite3 - we need to bundle it to avoid conflicts
# with better-sqlite3's embedded SQLite
SKIP_LIBS=(
    "linux-vdso.so"
    "libc.so"
    "libm.so"
    "libpthread.so"
    "libdl.so"
    "librt.so"
    "ld-linux"
    "libgcc_s.so"
    "libstdc++.so"
)

should_skip() {
    local lib="$1"
    for skip in "${SKIP_LIBS[@]}"; do
        if [[ "$lib" == *"$skip"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to copy a library
copy_lib() {
    local src="$1"
    local dest_dir="$2"
    local basename=$(basename "$src")

    if [ -f "$dest_dir/$basename" ]; then
        return 0  # Already copied
    fi

    if should_skip "$basename"; then
        return 0  # Skip system library
    fi

    # Follow symlinks to get the actual file
    local real_src=$(readlink -f "$src")
    local real_basename=$(basename "$real_src")

    echo "  Copying: $basename"

    # Copy the actual file
    cp "$real_src" "$dest_dir/$real_basename"

    # Create symlink if needed
    if [ "$basename" != "$real_basename" ]; then
        ln -sf "$real_basename" "$dest_dir/$basename"
    fi
}

# Collect all dependencies recursively
declare -A PROCESSED
LIBS_TO_PROCESS=("$MOD_SPATIALITE")

echo ""
echo "Collecting dependencies..."

while [ ${#LIBS_TO_PROCESS[@]} -gt 0 ]; do
    # Pop first library
    LIB="${LIBS_TO_PROCESS[0]}"
    LIBS_TO_PROCESS=("${LIBS_TO_PROCESS[@]:1}")

    # Skip if already processed
    if [ -n "${PROCESSED[$LIB]}" ]; then
        continue
    fi
    PROCESSED[$LIB]=1

    # Copy the library
    if [ -f "$LIB" ]; then
        copy_lib "$LIB" "$OUTPUT_DIR"

        # Get dependencies
        for DEP in $(get_deps "$LIB"); do
            if [ -f "$DEP" ] && [ -z "${PROCESSED[$DEP]}" ]; then
                if ! should_skip "$(basename $DEP)"; then
                    LIBS_TO_PROCESS+=("$DEP")
                fi
            fi
        done
    fi
done

echo ""
echo "Fixing library rpaths..."

# Fix all library rpaths to use $ORIGIN
for LIB in "$OUTPUT_DIR"/*.so*; do
    if [ -L "$LIB" ]; then
        continue  # Skip symlinks
    fi

    BASENAME=$(basename "$LIB")
    echo "  Fixing: $BASENAME"

    # Set rpath to look in the same directory
    patchelf --set-rpath '$ORIGIN' "$LIB" 2>/dev/null || true
done

# Rename the main module to a consistent name
MAIN_SO=$(find "$OUTPUT_DIR" -name "mod_spatialite*.so*" -type f | head -1)
if [ -n "$MAIN_SO" ] && [ "$(basename $MAIN_SO)" != "mod_spatialite.so" ]; then
    # Create symlink with standard name
    ln -sf "$(basename $MAIN_SO)" "$OUTPUT_DIR/mod_spatialite.so"
fi

# Verify the bundle
echo ""
echo "=== Verification ==="
echo "Files in bundle:"
ls -la "$OUTPUT_DIR"

echo ""
echo "mod_spatialite dependencies after fixing:"
ldd "$OUTPUT_DIR/mod_spatialite.so" 2>/dev/null || echo "(ldd may not work without system libs)"

echo ""
echo "Checking for unresolved dependencies:"
for LIB in "$OUTPUT_DIR"/*.so*; do
    if [ -L "$LIB" ]; then continue; fi
    UNRESOLVED=$(ldd "$LIB" 2>/dev/null | grep "not found" || true)
    if [ -n "$UNRESOLVED" ]; then
        echo "  $(basename $LIB): $UNRESOLVED"
    fi
done

echo ""
echo "Verifying libsqlite3 is bundled (required to avoid conflicts with better-sqlite3):"
if ls "$OUTPUT_DIR"/libsqlite3* >/dev/null 2>&1; then
    echo "  OK: libsqlite3 is bundled"
    ls -la "$OUTPUT_DIR"/libsqlite3*
else
    echo "  WARNING: libsqlite3 not found in bundle!"
fi

echo ""
echo "=== Bundle complete ==="
echo "Output directory: $OUTPUT_DIR"
