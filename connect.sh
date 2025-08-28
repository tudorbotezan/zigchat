#!/bin/bash

# Easy connect script for Bitchat TUI
# Default: Connect to 9q geohash on relay.damus.io
# Usage: ./connect.sh [geohash] [relay] [--debug]

GEOHASH="${1:-9q}"
RELAY="${2:-wss://relay.damus.io}"
DEBUG=""

# Check for debug flag in any position
for arg in "$@"; do
    if [ "$arg" = "--debug" ]; then
        DEBUG="--debug"
    fi
done

echo "🚀 Connecting to geohash $GEOHASH on $RELAY..."
echo "📍 Location: Central California (36.5625, -118.1250)"
if [ -n "$DEBUG" ]; then
    echo "🔧 Debug mode enabled"
fi
echo ""

# Use 'chat' for interactive mode, pass debug flag if present
./zig-out/bin/bitchat chat "$GEOHASH" "$RELAY" $DEBUG