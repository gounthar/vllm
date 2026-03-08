#!/bin/bash

# Detect packages built from source in pip install logs
# Usage: ./scripts/detect-source-builds.sh <logfile> [--json]
#
# Parses pip output to find packages that were compiled from source
# instead of installed from a prebuilt wheel. These are candidates
# for adding to the riscv64-python-wheels index.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <pip-log-file> [--json]"
    echo ""
    echo "Scans a pip install log for packages built from source."
    echo "Use --json to output machine-readable JSON."
    exit 1
fi

LOGFILE="$1"
JSON_MODE="${2:-}"

if [ ! -f "$LOGFILE" ]; then
    echo "ERROR: File not found: $LOGFILE"
    exit 1
fi

# Packages built from source show "Building wheel for <name>"
# Packages from prebuilt wheels show "Downloading <name>-<version>-<tags>.whl"
# or "Using cached <name>-<version>-<tags>.whl"

# Extract source-built packages
SOURCE_BUILT=$(grep -oP '(?<=Building wheel for )\S+' "$LOGFILE" | sort -u)

# Extract downloaded wheels (prebuilt)
PREBUILT=$(grep -oP '(?<=Downloading |Using cached )\S+\.whl' "$LOGFILE" | \
    sed 's/-[0-9].*//' | sort -u)

# Extract successfully built versions
BUILT_VERSIONS=$(grep -oP '(?<=Successfully built ).*' "$LOGFILE" | tr ' ' '\n' | sort -u)

if [ "$JSON_MODE" = "--json" ]; then
    echo "{"
    echo '  "source_built": ['
    first=true
    for pkg in $SOURCE_BUILT; do
        ver=$(echo "$BUILT_VERSIONS" | grep -i "^$pkg" | head -1)
        if [ "$first" = true ]; then first=false; else echo ","; fi
        printf '    {"package": "%s", "version": "%s"}' "$pkg" "${ver:-unknown}"
    done
    echo ""
    echo "  ],"
    echo "  \"prebuilt_count\": $(echo "$PREBUILT" | grep -c . || echo 0),"
    echo "  \"source_built_count\": $(echo "$SOURCE_BUILT" | grep -c . || echo 0)"
    echo "}"
else
    if [ -n "$SOURCE_BUILT" ]; then
        echo "=== Packages built from source (missing riscv64 wheel) ==="
        for pkg in $SOURCE_BUILT; do
            ver=$(echo "$BUILT_VERSIONS" | grep -i "^$pkg" | head -1)
            echo "  - $pkg${ver:+ ($ver)}"
        done
        echo ""
        prebuilt_count=$(echo "$PREBUILT" | grep -c . || echo 0)
        source_count=$(echo "$SOURCE_BUILT" | grep -c . || echo 0)
        echo "Summary: $source_count from source, $prebuilt_count prebuilt"
        echo ""
        echo "To add these to the riscv64 wheel index:"
        echo "  1. Fork the upstream repo into gounthar/"
        echo "  2. Add build-riscv64.yml workflow"
        echo "  3. Register runners and trigger build"
        echo "  4. See: https://github.com/gounthar/riscv64-python-wheels"
    else
        echo "All packages installed from prebuilt wheels."
    fi
fi
