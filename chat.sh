#!/bin/bash

# Interactive chat script for Bitchat
# Default: Connect to 9q geohash (Central California) on relay.damus.io

GEOHASH="${1:-9q}"
RELAY="${2:-wss://relay.damus.io}"

echo "🗨️  Starting Bitchat Interactive Mode..."
echo "📍 Geohash: $GEOHASH (coordinates: 36.5625, -118.1250)"
echo "🌐 Relay: $RELAY"
echo ""

./zig-out/bin/bitchat chat "$GEOHASH" "$RELAY"