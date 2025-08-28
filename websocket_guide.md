# Websocket.zig Usage Guide

## Library Overview
The karlseguin/websocket.zig library is primarily designed for websocket servers in Zig. For client connections, you'll need a different approach.

## Current Implementation Issue
The existing code in `src/nostr/ws.zig` attempts to use websocket client methods that don't match the library's API. The library focuses on server-side websocket handling.

## For Bitchat Geohash Channel Subscription

### Required Steps
1. Use a websocket client library or implement raw websocket protocol
2. Connect to bitchat websocket endpoint
3. Send subscription message for geohash channel
4. Handle incoming messages

### Message Format for Nostr/Bitchat
```json
["REQ", "subscription_id", {"kinds": [1], "tags": {"g": ["geohash_value"]}}]
```

### Key Considerations
- Need proper websocket client implementation
- Handle connection lifecycle (connect, disconnect, reconnect)
- Parse JSON messages from bitchat
- Implement error handling and timeouts

### Alternative Approach
Consider using:
- Raw TCP socket with websocket protocol implementation
- Different websocket client library for Zig
- HTTP client with websocket upgrade handling

### Current Code Fixes Needed
The existing `NostrClient` in `src/nostr/ws.zig` needs:
- Replace websocket.connect() with proper client initialization
- Implement websocket handshake
- Add JSON parsing for Nostr protocol
- Add geohash channel subscription logic