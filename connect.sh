#!/bin/bash

# Easy connect script for Bitchat TUI
# Default: Connect to 9q geohash on relay.damus.io

GEOHASH="${1:-9q}"
RELAY="${2:-wss://relay.damus.io}"

echo "🚀 Connecting to geohash $GEOHASH on $RELAY..."
echo "📍 Location: Central California (36.5625, -118.1250)"
echo ""

# Use 'chat' for interactive mode, or 'channel' for read-only
./zig-out/bin/bitchat chat "$GEOHASH" "$RELAY"