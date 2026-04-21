#!/bin/bash
###############################################
#  ITAgent Patch Generator
#  Run on ansible-host after making changes
#  Usage: ./patch_gen.sh <version> <description> <file1> [file2] ...
#  Example: ./patch_gen.sh 3.4.3.0 "Fix login bug" webapp/app.py webapp/services/auth_service.py
###############################################
set -e

ITAGENT_HOME="/opt/inspection"

if [ $# -lt 3 ]; then
    echo "Usage: $0 <version> <description> <file1> [file2] ..."
    echo "Example: $0 3.4.3.0 'Fix login' webapp/app.py webapp/templates/base.html"
    echo ""
    echo "Paths are relative to $ITAGENT_HOME"
    exit 1
fi

VER="$1"; shift
DESC="$1"; shift
FILES="$@"

TIMESTAMP=$(date +%Y%m%d_%H%M)
PATCH_DIR="/tmp/patch_v${VER}_${TIMESTAMP}"
mkdir -p "$PATCH_DIR/files"

# Copy patch_apply.sh
cat > "$PATCH_DIR/patch_apply.sh" << 'APPLYSCRIPT'
APPLYSCRIPT_PLACEHOLDER
APPLYSCRIPT

# Generate patch_info.txt
echo "VERSION=${VER}" > "$PATCH_DIR/patch_info.txt"
echo "DESC=${DESC}" >> "$PATCH_DIR/patch_info.txt"
echo "FILES=${FILES}" >> "$PATCH_DIR/patch_info.txt"
echo "DATE=$(date '+%Y-%m-%d %H:%M')" >> "$PATCH_DIR/patch_info.txt"

# Copy changed files
for f in $FILES; do
    SRC="$ITAGENT_HOME/$f"
    if [ -f "$SRC" ]; then
        mkdir -p "$PATCH_DIR/files/$(dirname "$f")"
        cp "$SRC" "$PATCH_DIR/files/$f"
        echo "  + $f"
    else
        echo "  WARN: $SRC not found, skipping"
    fi
done

# Package
PATCH_FILE="/tmp/patch_v${VER}_${TIMESTAMP}.tar.gz"
tar czf "$PATCH_FILE" -C "$PATCH_DIR" .
SIZE=$(du -h "$PATCH_FILE" | cut -f1)

echo ""
echo "=========================================="
echo "  Patch created: $PATCH_FILE"
echo "  Size: $SIZE"
echo "  Version: $VER"
echo "  Files: $(echo $FILES | wc -w) files"
echo "=========================================="
echo ""
echo "  Send via email, then on target:"
echo "  mkdir /tmp/patch && cd /tmp/patch"
echo "  tar xzf patch_v${VER}_${TIMESTAMP}.tar.gz"
echo "  chmod +x patch_apply.sh && ./patch_apply.sh"
