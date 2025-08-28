# WebSocket Implementation Plan for Bitchat TUI

## Current Situation Analysis

### What We Have
1. **Working TUI** - Message display and buffer management works
2. **Nostr Protocol Knowledge** - Correct message formats for subscriptions
3. **Simulated Client** - Shows the expected flow
4. **Two WebSocket Libraries** - But both have compatibility issues with Zig 0.14.1

### Issues Found
- `karlseguin/websocket.zig` - Has std.Io API incompatibility with Zig 0.14.1
- `ianic/websocket.zig` - Different API structure, requires stream-based approach
- Need TLS support for wss:// connections to Nostr relays

## Implementation Strategy

### Option 1: Use ianic/websocket.zig (Recommended)
This library appears simpler and more compatible. Located in `lib/ws/`.

**Steps:**
1. Create a TLS stream using std.crypto.tls.Client
2. Use the stream with websocket.client() function
3. Handle the WebSocket upgrade manually
4. Implement message framing

**Pros:**
- Simpler API
- Already in our lib folder
- More likely to work with Zig 0.14

**Cons:**
- Requires manual stream handling
- Less documentation

### Option 2: Implement Minimal WebSocket Client
Create our own minimal implementation focused on Nostr needs.

**Steps:**
1. Use std.http.Client for initial connection
2. Send WebSocket upgrade headers
3. Implement basic frame parsing (text frames only)
4. Skip advanced features (compression, extensions)

**Pros:**
- Full control
- Minimal dependencies
- Can optimize for Nostr use case

**Cons:**
- More work
- Need to handle edge cases

### Option 3: Use External Process
Call a small helper program (Python/Node.js) for WebSocket.

**Pros:**
- Quick to implement
- Reliable WebSocket support

**Cons:**
- External dependency
- Not pure Zig
- Larger binary size

## Recommended Implementation Path

### Phase 1: Basic WebSocket Client (2-3 hours)
```zig
// src/websocket_simple.zig
pub const SimpleWebSocket = struct {
    allocator: std.mem.Allocator,
    stream: ?std.net.Stream,
    tls_client: ?*std.crypto.tls.Client,
    
    pub fn connect(url: []const u8) !void
    pub fn send(message: []const u8) !void
    pub fn receive() ![]u8
    pub fn close() void
};
```

### Phase 2: Nostr Integration (1-2 hours)
```zig
// Update src/nostr_client.zig
- Replace simulated client with SimpleWebSocket
- Add JSON parsing for ["EVENT", ...] messages
- Extract content field from events
- Handle EOSE, NOTICE, OK messages
```

### Phase 3: TUI Integration (1 hour)
```zig
// Connect real WebSocket to existing TUI
- Replace simulateMessages() with real receive loop
- Add connection status indicator
- Handle disconnections gracefully
```

## Detailed Implementation Steps

### Step 1: Create Basic TLS Connection
```zig
const uri = try std.Uri.parse(relay_url);
const stream = try net.tcpConnectToHost(allocator, uri.host.?, uri.port orelse 443);

// Wrap in TLS for wss://
var tls_client = try std.crypto.tls.Client.init(stream, allocator, uri.host.?);
try tls_client.handshake();
```

### Step 2: WebSocket Handshake
```zig
// Generate random key
var key_bytes: [16]u8 = undefined;
std.crypto.random.bytes(&key_bytes);
const key = std.base64.standard.Encoder.encode(&key_bytes);

// Send upgrade request
const request = try std.fmt.allocPrint(allocator,
    "GET {s} HTTP/1.1\r\n" ++
    "Host: {s}\r\n" ++
    "Upgrade: websocket\r\n" ++
    "Connection: Upgrade\r\n" ++
    "Sec-WebSocket-Key: {s}\r\n" ++
    "Sec-WebSocket-Version: 13\r\n\r\n",
    .{ uri.path orelse "/", uri.host.?, key }
);
```

### Step 3: Frame Parser
```zig
pub fn parseFrame(data: []const u8) !Message {
    if (data.len < 2) return error.IncompleteFrame;
    
    const fin = (data[0] & 0x80) != 0;
    const opcode = data[0] & 0x0F;
    const masked = (data[1] & 0x80) != 0;
    var payload_len: usize = data[1] & 0x7F;
    var offset: usize = 2;
    
    // Handle extended payload length...
    // Extract and unmask payload...
    // Return parsed message
}
```

### Step 4: Nostr Message Handler
```zig
pub fn handleNostrMessage(json: []const u8) !NostrEvent {
    // Parse ["EVENT", "sub_id", {...}]
    // Extract: content, pubkey, created_at, tags
    // Return structured event
}
```

## Testing Plan

### Test 1: Basic Connection
```bash
./zig-out/bin/bitchat test-ws wss://relay.damus.io
# Should connect and show "Connected"
```

### Test 2: Subscribe to Channel
```bash
./zig-out/bin/bitchat channel 9q wss://relay.damus.io
# Should show real messages from the relay
```

### Test 3: Multiple Relays
```bash
./zig-out/bin/bitchat channel global wss://nos.lol
# Test with different relay
```

## Error Handling

1. **Connection Failures**
   - Retry with exponential backoff
   - Try next relay in list

2. **Parse Errors**
   - Log and skip malformed messages
   - Don't crash on bad JSON

3. **Network Issues**
   - Detect disconnection
   - Auto-reconnect with state preservation

## Memory Management

1. **Message Buffer**
   - Keep last 100 messages
   - Free old messages when buffer full
   - Use arena allocator for temp parsing

2. **Connection Resources**
   - Proper cleanup in defer blocks
   - Close TLS and TCP on disconnect

## Timeline

- **Hour 1-2**: Implement basic WebSocket handshake
- **Hour 3-4**: Add frame parsing and sending
- **Hour 5**: Integrate with Nostr protocol
- **Hour 6**: Connect to TUI and test
- **Hour 7-8**: Error handling and polish

## Success Criteria

✅ Connect to wss://relay.damus.io
✅ Send subscription for #9q channel  
✅ Receive and parse EVENT messages
✅ Display messages in TUI
✅ Handle disconnections gracefully
✅ Memory efficient (< 10MB RAM)
✅ Binary size < 2MB

## Next Immediate Steps

1. Check if ianic/ws library can work with minor modifications
2. If not, implement minimal WebSocket client
3. Test with relay.damus.io first
4. Add proper JSON parsing
5. Connect to existing TUI code

## Alternative Quick Solution

If WebSocket implementation proves too complex, create a bridge:
```bash
# Python WebSocket bridge
python3 ws_bridge.py | ./zig-out/bin/bitchat stdin-reader
```

This allows us to get working functionality quickly while developing the pure Zig solution.