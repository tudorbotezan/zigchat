# WebSocket Implementation - Concrete Steps

## Working Example Found!
The `lib/ws` library has a working client example in `examples/autobahn_client.zig`.

## Implementation Steps

### Step 1: Create Working WebSocket Client
Based on the autobahn example, here's what we need:

```zig
// src/websocket_client.zig
const std = @import("std");
const ws = @import("ws");  // Need to add this import path

pub const WsClient = struct {
    allocator: std.mem.Allocator,
    tcp: std.net.Stream,
    client: ws.Stream,
    
    pub fn connect(allocator: std.mem.Allocator, url: []const u8) !WsClient {
        const uri = try std.Uri.parse(url);
        const host = uri.host orelse return error.InvalidUrl;
        const port = uri.port orelse 443;
        
        // For wss:// we need TLS wrapper
        var tcp = try std.net.tcpConnectToHost(allocator, host, port);
        
        // If wss://, wrap in TLS here
        if (std.mem.eql(u8, uri.scheme, "wss")) {
            // Need TLS wrapper
        }
        
        var client = try ws.client(allocator, tcp.reader(), tcp.writer(), url);
        
        return WsClient{
            .allocator = allocator,
            .tcp = tcp,
            .client = client,
        };
    }
    
    pub fn sendText(self: *WsClient, text: []const u8) !void {
        const msg = ws.Message{
            .encoding = .text,
            .payload = text,
        };
        try self.client.sendMessage(msg);
    }
    
    pub fn receive(self: *WsClient) !?[]const u8 {
        if (self.client.nextMessage()) |msg| {
            defer msg.deinit();
            return try self.allocator.dupe(u8, msg.payload);
        }
        return null;
    }
    
    pub fn deinit(self: *WsClient) void {
        self.client.deinit();
        self.tcp.close();
    }
};
```

### Step 2: Add TLS Support
For wss:// connections, we need to wrap the TCP stream:

```zig
// src/tls_stream.zig
const std = @import("std");

pub fn wrapTls(tcp: std.net.Stream, host: []const u8) !TlsStream {
    var tls_client = try std.crypto.tls.Client.init(tcp, host);
    try tls_client.handshake();
    
    return TlsStream{
        .tcp = tcp,
        .tls = tls_client,
    };
}

const TlsStream = struct {
    tcp: std.net.Stream,
    tls: std.crypto.tls.Client,
    
    pub fn reader(self: *TlsStream) Reader {
        return self.tls.reader();
    }
    
    pub fn writer(self: *TlsStream) Writer {
        return self.tls.writer();
    }
    
    pub fn close(self: *TlsStream) void {
        self.tls.close();
        self.tcp.close();
    }
};
```

### Step 3: Update build.zig
Add the ws library module:

```zig
// build.zig additions
const ws_module = b.addModule("ws", .{
    .root_source_file = b.path("lib/ws/src/main.zig"),
});

exe.root_module.addImport("ws", ws_module);
```

### Step 4: Integrate with Nostr Client
Update the Nostr client to use real WebSocket:

```zig
// src/nostr_real.zig
const std = @import("std");
const WsClient = @import("websocket_client.zig").WsClient;

pub const NostrRealClient = struct {
    allocator: std.mem.Allocator,
    ws: WsClient,
    subscription_id: []const u8 = "1",
    
    pub fn connect(allocator: std.mem.Allocator, relay_url: []const u8) !NostrRealClient {
        var ws = try WsClient.connect(allocator, relay_url);
        
        return NostrRealClient{
            .allocator = allocator,
            .ws = ws,
        };
    }
    
    pub fn subscribeToChannel(self: *NostrRealClient, channel: []const u8) !void {
        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer, 
            \\["REQ","{s}",{{"kinds":[1],"#t":["{s}"],"limit":100}}]
        , .{self.subscription_id, channel});
        
        try self.ws.sendText(req);
    }
    
    pub fn receiveMessage(self: *NostrRealClient) !?NostrMessage {
        if (try self.ws.receive()) |raw_msg| {
            defer self.allocator.free(raw_msg);
            return try parseNostrMessage(self.allocator, raw_msg);
        }
        return null;
    }
    
    pub fn deinit(self: *NostrRealClient) void {
        self.ws.deinit();
    }
};
```

### Step 5: Parse Nostr Messages
```zig
const NostrMessage = struct {
    type: MessageType,
    content: ?[]const u8 = null,
    author: ?[]const u8 = null,
    timestamp: ?i64 = null,
};

const MessageType = enum {
    EVENT,
    EOSE,
    NOTICE,
    OK,
    AUTH,
};

fn parseNostrMessage(allocator: std.mem.Allocator, json: []const u8) !NostrMessage {
    // Basic parsing - in production use proper JSON parser
    if (std.mem.startsWith(u8, json, "[\"EVENT\"")) {
        // Extract content field
        const content_marker = "\"content\":\"";
        if (std.mem.indexOf(u8, json, content_marker)) |start| {
            const content_begin = start + content_marker.len;
            // Find end of content...
            // Return parsed message
        }
    }
    // Handle other message types...
}
```

## File Changes Needed

### 1. build.zig
- Add ws module import
- Link with system TLS library if needed

### 2. src/websocket_client.zig (NEW)
- Implement WsClient struct
- Handle TCP connection
- Wrap with TLS for wss://

### 3. src/nostr_real.zig (NEW)
- Real Nostr client using WebSocket
- Message parsing
- Subscription management

### 4. src/main.zig
- Update cmdChannel to use NostrRealClient
- Add error handling for connection failures
- Show real messages instead of simulation

## Testing Strategy

### Test 1: Raw WebSocket Connection
```bash
# Test basic ws:// connection (no TLS)
./zig-out/bin/bitchat test-ws ws://echo.websocket.org
```

### Test 2: TLS WebSocket Connection
```bash
# Test wss:// with TLS
./zig-out/bin/bitchat test-ws wss://relay.damus.io
```

### Test 3: Full Nostr Integration
```bash
# Connect and subscribe to channel
./zig-out/bin/bitchat channel 9q wss://relay.damus.io
```

## Potential Issues & Solutions

### Issue 1: TLS with ws library
The ws library expects reader/writer interfaces. TLS wrapping needs to provide these.

**Solution**: Create adapter that implements reader() and writer() methods for TLS stream.

### Issue 2: Zig 0.14.1 Compatibility
Some APIs might have changed.

**Solution**: Use simpler interfaces, avoid newer Zig features.

### Issue 3: JSON Parsing
Nostr messages are complex JSON.

**Solution**: Start with basic string parsing, add proper JSON later.

## Quick Win Alternative
If the above proves complex, we can create a minimal implementation:

```zig
// Minimal WebSocket just for Nostr text messages
pub fn connectAndSubscribe(relay: []const u8, channel: []const u8) !void {
    // 1. TCP connect
    // 2. Send HTTP upgrade
    // 3. Send subscription
    // 4. Read frames in loop
    // 5. Parse and print messages
}
```

## Next Actions

1. ✅ Try compiling with ws module added to build.zig
2. ✅ Create basic websocket_client.zig
3. ✅ Test with ws://echo.websocket.org first
4. ✅ Add TLS support for wss://
5. ✅ Connect to real Nostr relay
6. ✅ Parse and display messages

This approach uses the existing ws library that's already in our project, avoiding compatibility issues with external libraries.