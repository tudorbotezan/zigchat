#!/bin/bash

# Easy connect script for Bitchat TUI
# Default: Connect to #9q channel on relay.damus.io

CHANNEL="${1:-tech}"
RELAY="${2:-wss://relay.damus.io}"

echo "🚀 Connecting to #$CHANNEL on $RELAY..."
echo ""

./zig-out/bin/bitchat channel "$CHANNEL" "$RELAY"