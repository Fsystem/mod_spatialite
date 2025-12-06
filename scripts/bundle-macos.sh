#!/bin/bash
set -e

# Bundle mod_spatialite and all its dependencies for macOS
# Usage: ./bundle-macos.sh [x64|arm64]
# Note: Compatible with bash 3.2 (macOS default)

ARCH="${1:-arm64}"
OUTPUT_DIR="output"

echo "=== Bundling mod_spatialite for macOS $ARCH ==="

# Determine Homebrew prefix based on architecture
if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

# Find mod_spatialite
MOD_SPATIALITE="$BREW_PREFIX/lib/mod_spatialite.dylib"

if [ ! -f "$MOD_SPATIALITE" ]; then
    echo "Error: mod_spatialite.dylib not found at $MOD_SPATIALITE"
    echo "Install with: brew install libspatialite"
    exit 1
fi

echo "Found mod_spatialite at: $MOD_SPATIALITE"

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# File to track processed libraries (bash 3.2 compatible)
PROCESSED_FILE=$(mktemp)
trap "rm -f $PROCESSED_FILE" EXIT

is_processed() {
    grep -q "^$1$" "$PROCESSED_FILE" 2>/dev/null
}

mark_processed() {
    echo "$1" >> "$PROCESSED_FILE"
}

# Function to get all dylib dependencies
get_deps() {
    local lib="$1"
    otool -L "$lib" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^/usr/lib" | grep -v "^/System" || true
}

# Function to copy a library and fix its install name
copy_lib() {
    local src="$1"
    local dest_dir="$2"
    local basename=$(basename "$src")

    if [ -f "$dest_dir/$basename" ]; then
        return 0  # Already copied
    fi

    echo "  Copying: $basename"
    cp "$src" "$dest_dir/"

    # Fix the library's own install name to use @loader_path
    install_name_tool -id "@loader_path/$basename" "$dest_dir/$basename" 2>/dev/null || true
}

# Collect all dependencies recursively using a queue file
QUEUE_FILE=$(mktemp)
trap "rm -f $PROCESSED_FILE $QUEUE_FILE" EXIT

echo "$MOD_SPATIALITE" > "$QUEUE_FILE"

echo ""
echo "Collecting dependencies..."

while [ -s "$QUEUE_FILE" ]; do
    # Read first line and remove it
    LIB=$(head -1 "$QUEUE_FILE")
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

    # Skip if already processed
    if is_processed "$LIB"; then
        continue
    fi
    mark_processed "$LIB"

    # Copy the library
    if [ -f "$LIB" ]; then
        copy_lib "$LIB" "$OUTPUT_DIR"

        # Get dependencies
        for DEP in $(get_deps "$LIB"); do
            RESOLVED=""

            if [[ "$DEP" == @* ]]; then
                # Handle @rpath, @loader_path, @executable_path
                BASENAME=$(basename "$DEP")
                if [ -f "$BREW_PREFIX/lib/$BASENAME" ]; then
                    RESOLVED="$BREW_PREFIX/lib/$BASENAME"
                fi
            elif [ -f "$DEP" ]; then
                RESOLVED="$DEP"
            elif [ -f "$BREW_PREFIX/lib/$(basename "$DEP")" ]; then
                RESOLVED="$BREW_PREFIX/lib/$(basename "$DEP")"
            fi

            if [ -n "$RESOLVED" ] && ! is_processed "$RESOLVED"; then
                echo "$RESOLVED" >> "$QUEUE_FILE"
            fi
        done
    fi
done

echo ""
echo "Bundling libsqlite3 from Homebrew (to avoid system SQLite conflicts)..."

# PROJ links to /usr/lib/libsqlite3.dylib which conflicts with better-sqlite3's embedded SQLite.
# We bundle Homebrew's libsqlite3 and patch PROJ to use it instead.
HOMEBREW_SQLITE="$BREW_PREFIX/opt/sqlite/lib/libsqlite3.dylib"
if [ -f "$HOMEBREW_SQLITE" ]; then
    echo "  Copying: libsqlite3.dylib (from Homebrew)"
    cp "$HOMEBREW_SQLITE" "$OUTPUT_DIR/libsqlite3.dylib"
    install_name_tool -id "@loader_path/libsqlite3.dylib" "$OUTPUT_DIR/libsqlite3.dylib" 2>/dev/null || true
else
    echo "  Warning: Homebrew SQLite not found at $HOMEBREW_SQLITE"
fi

echo ""
echo "Fixing library references..."

# Fix all library references to use @loader_path
for LIB in "$OUTPUT_DIR"/*.dylib; do
    [ -f "$LIB" ] || continue
    BASENAME=$(basename "$LIB")
    echo "  Fixing: $BASENAME"

    for DEP in $(get_deps "$LIB"); do
        DEP_BASENAME=$(basename "$DEP")
        if [ -f "$OUTPUT_DIR/$DEP_BASENAME" ]; then
            install_name_tool -change "$DEP" "@loader_path/$DEP_BASENAME" "$LIB" 2>/dev/null || true
        fi
    done

    # Also fix /usr/lib/libsqlite3.dylib references to use our bundled version
    if otool -L "$LIB" 2>/dev/null | grep -q "/usr/lib/libsqlite3.dylib"; then
        echo "    Patching libsqlite3 reference in $BASENAME"
        install_name_tool -change "/usr/lib/libsqlite3.dylib" "@loader_path/libsqlite3.dylib" "$LIB" 2>/dev/null || true
    fi
done

echo ""
echo "Re-signing libraries (required after install_name_tool modifications)..."

# Re-sign all libraries - required on Apple Silicon after modifying with install_name_tool
for LIB in "$OUTPUT_DIR"/*.dylib; do
    [ -f "$LIB" ] || continue
    BASENAME=$(basename "$LIB")
    echo "  Signing: $BASENAME"
    codesign --force --sign - "$LIB" 2>/dev/null || true
done

# Verify the bundle
echo ""
echo "=== Verification ==="
echo "Files in bundle:"
ls -la "$OUTPUT_DIR"

echo ""
echo "mod_spatialite dependencies after fixing:"
otool -L "$OUTPUT_DIR/mod_spatialite.dylib"

echo ""
echo "libproj dependencies after fixing:"
otool -L "$OUTPUT_DIR/libproj.25.dylib"

# Verify no system SQLite references remain
echo ""
echo "Checking for remaining /usr/lib/libsqlite3 references..."
if grep -r "/usr/lib/libsqlite3" "$OUTPUT_DIR" 2>/dev/null; then
    echo "WARNING: Found remaining system SQLite references!"
else
    echo "OK: No system SQLite references found"
fi

echo ""
echo "=== Bundle complete ==="
echo "Output directory: $OUTPUT_DIR"
