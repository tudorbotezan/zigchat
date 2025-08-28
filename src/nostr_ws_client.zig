const std = @import("std");
const WebSocketClient = @import("websocket_client.zig").WebSocketClient;
const TlsWebSocketClient = @import("websocket_tls.zig").TlsWebSocketClient;
const nip11 = @import("nostr/nip11.zig");

pub const NostrWsClient = struct {
    allocator: std.mem.Allocator,
    ws_client: ?WebSocketClient = null,
    tls_client: ?TlsWebSocketClient = null,
    subscription_id: []const u8 = "1",
    is_tls: bool,
    url: []const u8,
    relay_info: ?nip11.RelayInfo = null,
    can_write: bool = true,
    debug_mode: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, relay_url: []const u8, debug_mode: bool) Self {
        const is_tls = std.mem.startsWith(u8, relay_url, "wss://");

        return .{
            .allocator = allocator,
            .is_tls = is_tls,
            .url = relay_url,
            .debug_mode = debug_mode,
        };
    }

    pub fn connect(self: *Self) !void {
        // First, fetch NIP-11 relay info
        self.relay_info = nip11.fetchRelayInfo(self.allocator, self.url) catch null;
        
        // Check if relay allows writes
        if (self.relay_info) |info| {
            if (info.restricted_writes) {
                self.can_write = false;
                std.debug.print("[{s}] WARNING: Relay has restricted writes\n", .{self.url});
            }
            if (info.auth_required) {
                std.debug.print("[{s}] Note: Relay requires authentication (NIP-42)\n", .{self.url});
            }
        }
        
        // Connect WebSocket
        if (self.is_tls) {
            self.tls_client = TlsWebSocketClient.init(self.allocator, self.url);
            try self.tls_client.?.connect();
        } else {
            self.ws_client = WebSocketClient.init(self.allocator, self.url);
            try self.ws_client.?.connect();
        }
        std.debug.print("[{s}] Connected (can_write={})\n", .{ self.url, self.can_write });
    }

    pub fn subscribeToChannel(self: *Self, channel: []const u8) !void {
        // REAL-TIME MODE ONLY - Subscribe from NOW to get only new incoming messages
        const now = std.time.timestamp();

        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","{s}",{{"#g":["{s}"],"since":{d}}}]
        , .{ self.subscription_id, channel, now });

        if (self.is_tls) {
            try self.tls_client.?.sendText(req);
        } else {
            try self.ws_client.?.sendText(req);
        }
        if (self.debug_mode) {
            std.debug.print("Subscribed to REAL-TIME messages for geohash: {s}\n", .{channel});
        }
    }

    pub fn subscribeToChannelSmart(self: *Self, channel: []const u8, debug_mode: bool) !void {
        // BitChat-compatible subscription: kinds [1, 20000] with #g geotag
        // kind 1 = text notes (stored), kind 20000 = ephemeral location stream
        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","geo-{s}-live",{{"kinds":[1,20000],"#g":["{s}"],"limit":200}}]
        , .{ channel, channel });

        if (self.is_tls) {
            try self.tls_client.?.sendText(req);
        } else {
            try self.ws_client.?.sendText(req);
        }
        if (debug_mode) {
            std.debug.print("[{s}] Subscribed to kinds [1,20000] with #g geotag: {s}\n", .{ self.url, channel });
        }
    }

    pub fn subscribeToGlobal(self: *Self) !void {
        // REAL-TIME MODE - Subscribe from NOW
        const now = std.time.timestamp();

        var req_buffer: [256]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","{s}",{{"kinds":[1],"since":{d}}}]
        , .{ self.subscription_id, now });

        if (self.is_tls) {
            try self.tls_client.?.sendText(req);
        } else {
            try self.ws_client.?.sendText(req);
        }
        if (self.debug_mode) {
            std.debug.print("Subscribed to global feed\n", .{});
        }
    }

    pub fn receiveMessage(self: *Self) !?NostrMessage {
        const raw_msg = blk: {
            if (self.is_tls) {
                break :blk try self.tls_client.?.receive() orelse return null;
            } else {
                break :blk try self.ws_client.?.receive() orelse return null;
            }
        };
        defer self.allocator.free(raw_msg);

        // Log full raw response for debugging
        if (self.debug_mode) {
            std.debug.print("\n[FULL RAW RESPONSE]: {s}\n", .{raw_msg});
        }

        return parseNostrMessage(self.allocator, raw_msg) catch |err| {
            if (self.debug_mode) {
                std.debug.print("\n[PARSE ERROR]: Failed to parse: {}\n", .{err});
                std.debug.print("[FAILED MSG]: {s}\n", .{raw_msg});
            }
            return null;
        };
    }

    pub fn close(self: *Self) void {
        if (self.ws_client) |*client| {
            client.close();
        }
        if (self.tls_client) |*client| {
            client.close();
        }
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }
};

pub const NostrMessage = struct {
    type: MessageType,
    content: ?[]const u8 = null,
    author: ?[]const u8 = null,
    created_at: ?i64 = null,
    id: ?[]const u8 = null,
    event_id: ?[]const u8 = null, // For OK messages
    ok_status: ?bool = null, // For OK messages: true/false
    tags: ?[][]const u8 = null, // Add tags field to store parsed tags
    kind: ?u32 = null, // Event kind (1 = text, 20000 = ephemeral, etc.)
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const NostrMessage) void {
        if (self.content) |content| self.allocator.free(content);
        if (self.author) |author| self.allocator.free(author);
        if (self.id) |id| self.allocator.free(id);
        if (self.event_id) |event_id| self.allocator.free(event_id);
        if (self.tags) |tags| {
            for (tags) |tag| {
                self.allocator.free(tag);
            }
            self.allocator.free(tags);
        }
    }
};

pub const MessageType = enum {
    EVENT,
    EOSE,
    NOTICE,
    OK,
    AUTH,
    UNKNOWN,
};

fn parseNostrMessage(allocator: std.mem.Allocator, json_str: []const u8) !NostrMessage {
    // Basic parsing - identify message type
    var msg_type: MessageType = .UNKNOWN;
    var content: ?[]const u8 = null;
    var author: ?[]const u8 = null;
    var created_at: ?i64 = null;
    var event_id: ?[]const u8 = null;
    var ok_status: ?bool = null;
    var tags: ?[][]const u8 = null;
    var kind: ?u32 = null;

    if (std.mem.startsWith(u8, json_str, "[\"EVENT\"")) {
        msg_type = .EVENT;

        // Extract content field (tolerate whitespace after colon)
        if (findJsonStringValueStart(json_str, "content")) |val_start| {
            if (val_start < json_str.len and json_str[val_start] == '"') {
                const content_start = val_start + 1;
                const end = findStringEnd(json_str, content_start) orelse json_str.len;
                // Unescape the JSON string to handle escaped characters and unicode
                content = try unescapeJsonString(allocator, json_str[content_start..end]);
            }
        }

        // Extract event ID for deduplication
        if (findJsonStringValueStart(json_str, "id")) |val_start| {
            if (val_start < json_str.len and json_str[val_start] == '"') {
                const s = val_start + 1;
                const e = findStringEnd(json_str, s) orelse json_str.len;
                event_id = try allocator.dupe(u8, json_str[s..e]);
            }
        }

        // Extract pubkey (author)
        if (findJsonStringValueStart(json_str, "pubkey")) |val_start| {
            if (val_start < json_str.len and json_str[val_start] == '"') {
                const s = val_start + 1;
                const e = findStringEnd(json_str, s) orelse json_str.len;
                author = try allocator.dupe(u8, json_str[s..e]);
            }
        }

        // Extract tags to find nickname
        if (findJsonArrayStart(json_str, "tags")) |tags_start| {
            // Find the matching closing bracket
            var bracket_count: i32 = 1;
            var i = tags_start;
            while (i < json_str.len and bracket_count > 0) : (i += 1) {
                if (json_str[i] == '[') bracket_count += 1;
                if (json_str[i] == ']') bracket_count -= 1;
            }

            // Parse nickname tag if present - handle variations with/without spaces
            const tags_str = json_str[tags_start .. i - 1];
            // Try both with and without space after comma
            var n_tag_pos: ?usize = std.mem.indexOf(u8, tags_str, "[\"n\",\"");
            var prefix_len: usize = "[\"n\",\"".len;

            if (n_tag_pos == null) {
                n_tag_pos = std.mem.indexOf(u8, tags_str, "[\"n\", \"");
                prefix_len = "[\"n\", \"".len;
            }

            if (n_tag_pos) |pos| {
                const nick_start = pos + prefix_len;
                if (std.mem.indexOf(u8, tags_str[nick_start..], "\"")) |nick_end| {
                    // Only create tag if nickname is not empty
                    if (nick_end > 0) {
                        var tag_list = try allocator.alloc([]const u8, 2);
                        tag_list[0] = try allocator.dupe(u8, "n");
                        tag_list[1] = try unescapeJsonString(allocator, tags_str[nick_start .. nick_start + nick_end]);
                        tags = tag_list;
                    }
                }
            }
        }

        // Extract kind (event type)
        if (findJsonFieldValueStart(json_str, "kind")) |start| {
            var end = start;
            while (end < json_str.len and (json_str[end] >= '0' and json_str[end] <= '9')) : (end += 1) {}
            if (end > start) {
                kind = try std.fmt.parseInt(u32, json_str[start..end], 10);
            }
        }

        // Extract created_at (tolerate whitespace after colon)
        if (findJsonFieldValueStart(json_str, "created_at")) |start| {
            var end = start;
            while (end < json_str.len and (json_str[end] >= '0' and json_str[end] <= '9')) : (end += 1) {}
            if (end > start) {
                created_at = try std.fmt.parseInt(i64, json_str[start..end], 10);
            }
        }
    } else if (std.mem.startsWith(u8, json_str, "[\"EOSE\"")) {
        msg_type = .EOSE;
    } else if (std.mem.startsWith(u8, json_str, "[\"NOTICE\"")) {
        msg_type = .NOTICE;
        // Extract notice message
        if (findJsonString(json_str, "[\"NOTICE\",\"")) |notice_start| {
            const end = findStringEnd(json_str, notice_start) orelse json_str.len;
            content = try allocator.dupe(u8, json_str[notice_start..end]);
        }
    } else if (std.mem.startsWith(u8, json_str, "[\"OK\"")) {
        msg_type = .OK;
        // Parse OK message format: ["OK", "event_id", true/false, "message"]
        // Find event ID
        if (std.mem.indexOf(u8, json_str[6..], "\"")) |start| {
            const id_start = 6 + start + 1;
            if (std.mem.indexOf(u8, json_str[id_start..], "\"")) |end| {
                event_id = try allocator.dupe(u8, json_str[id_start..id_start + end]);
            }
        }
        // Find true/false status
        if (std.mem.indexOf(u8, json_str, "true")) |_| {
            ok_status = true;
        } else if (std.mem.indexOf(u8, json_str, "false")) |_| {
            ok_status = false;
        }
        // Find optional message
        var comma_count: usize = 0;
        var i: usize = 0;
        while (i < json_str.len) : (i += 1) {
            if (json_str[i] == ',' and comma_count < 3) {
                comma_count += 1;
                if (comma_count == 3) {
                    // Look for message after third comma
                    var j = i + 1;
                    while (j < json_str.len and json_str[j] != '"') : (j += 1) {}
                    if (j < json_str.len) {
                        const msg_start = j + 1;
                        if (std.mem.indexOf(u8, json_str[msg_start..], "\"")) |msg_end| {
                            content = try allocator.dupe(u8, json_str[msg_start..msg_start + msg_end]);
                        }
                    }
                }
            }
        }
    } else if (std.mem.startsWith(u8, json_str, "[\"AUTH\"")) {
        msg_type = .AUTH;
        // Extract challenge for AUTH handling
        if (findJsonString(json_str, "[\"AUTH\",\"")) |auth_start| {
            const end = findStringEnd(json_str, auth_start) orelse json_str.len;
            content = try allocator.dupe(u8, json_str[auth_start..end]);
        }
    }

    // Duplicate event_id if we have one since we use it for both fields
    const id_copy = if (event_id) |eid| try allocator.dupe(u8, eid) else null;
    
    return NostrMessage{
        .type = msg_type,
        .content = content,
        .author = author,
        .created_at = created_at,
        .id = event_id,  // Use original for 'id' field
        .event_id = id_copy,  // Use copy for 'event_id' field
        .ok_status = ok_status,
        .tags = tags,
        .kind = kind,
        .allocator = allocator,
    };
}

fn findJsonString(json: []const u8, marker: []const u8) ?usize {
    if (std.mem.indexOf(u8, json, marker)) |pos| {
        return pos + marker.len;
    }
    return null;
}

// Finds the start index of a JSON value for a given string key, allowing whitespace around ':'
fn findJsonStringValueStart(json: []const u8, key: []const u8) ?usize {
    // Build the needle "key"
    var buf: [128]u8 = undefined;
    const n = std.fmt.bufPrint(&buf, "\"{s}\"", .{key}) catch return null;
    const needle = buf[0..n.len];
    var pos = std.mem.indexOf(u8, json, needle) orelse return null;
    pos += needle.len;
    // Skip optional whitespace
    while (pos < json.len and (json[pos] == ' ' or json[pos] == '\n' or json[pos] == '\r' or json[pos] == '\t')) : (pos += 1) {}
    if (pos >= json.len or json[pos] != ':') return null;
    pos += 1;
    while (pos < json.len and (json[pos] == ' ' or json[pos] == '\n' or json[pos] == '\r' or json[pos] == '\t')) : (pos += 1) {}
    return if (pos < json.len) pos else null;
}

// For numeric fields; same behavior as above
fn findJsonFieldValueStart(json: []const u8, key: []const u8) ?usize {
    return findJsonStringValueStart(json, key);
}

// Finds the start (first element position) of an array value for a given key
fn findJsonArrayStart(json: []const u8, key: []const u8) ?usize {
    if (findJsonStringValueStart(json, key)) |pos| {
        var i = pos;
        while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
        if (i < json.len and json[i] == '[') return i + 1;
    }
    return null;
}

fn unescapeJsonString(allocator: std.mem.Allocator, escaped: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < escaped.len) {
        if (escaped[i] == '\\' and i + 1 < escaped.len) {
            switch (escaped[i + 1]) {
                'n' => try result.append('\n'),
                'r' => try result.append('\r'),
                't' => try result.append('\t'),
                '"' => try result.append('"'),
                '\\' => try result.append('\\'),
                'u' => {
                    // Handle Unicode escape sequences like \u0041 or \uD83D\uDE00 (emoji)
                    if (i + 5 < escaped.len) {
                        const hex_str = escaped[i + 2 .. i + 6];
                        const codepoint = std.fmt.parseInt(u16, hex_str, 16) catch {
                            // If parsing fails, just append the literal characters
                            try result.append(escaped[i]);
                            i += 1;
                            continue;
                        };

                        // Check for surrogate pair (for emojis and other chars > U+FFFF)
                        if (codepoint >= 0xD800 and codepoint <= 0xDBFF and i + 11 < escaped.len) {
                            if (escaped[i + 6] == '\\' and escaped[i + 7] == 'u') {
                                const low_hex = escaped[i + 8 .. i + 12];
                                const low = std.fmt.parseInt(u16, low_hex, 16) catch {
                                    // Not a valid surrogate pair, encode the high surrogate alone
                                    try encodeUtf8(&result, codepoint);
                                    i += 6;
                                    continue;
                                };

                                // Decode surrogate pair to full codepoint
                                const high = codepoint;
                                const full_codepoint = @as(u21, (high - 0xD800)) * 0x400 + (low - 0xDC00) + 0x10000;
                                try encodeUtf8(&result, full_codepoint);
                                i += 12;
                                continue;
                            }
                        }

                        try encodeUtf8(&result, codepoint);
                        i += 6;
                    } else {
                        try result.append(escaped[i]);
                        i += 1;
                    }
                },
                else => {
                    // Unknown escape sequence, keep the backslash
                    try result.append(escaped[i]);
                    i += 1;
                },
            }
            if (escaped[i + 1] != 'u') {
                i += 2;
            }
        } else {
            try result.append(escaped[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

fn encodeUtf8(result: *std.ArrayList(u8), codepoint: u21) !void {
    if (codepoint <= 0x7F) {
        try result.append(@intCast(codepoint));
    } else if (codepoint <= 0x7FF) {
        try result.append(@intCast(0xC0 | (codepoint >> 6)));
        try result.append(@intCast(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0xFFFF) {
        try result.append(@intCast(0xE0 | (codepoint >> 12)));
        try result.append(@intCast(0x80 | ((codepoint >> 6) & 0x3F)));
        try result.append(@intCast(0x80 | (codepoint & 0x3F)));
    } else {
        try result.append(@intCast(0xF0 | (codepoint >> 18)));
        try result.append(@intCast(0x80 | ((codepoint >> 12) & 0x3F)));
        try result.append(@intCast(0x80 | ((codepoint >> 6) & 0x3F)));
        try result.append(@intCast(0x80 | (codepoint & 0x3F)));
    }
}

fn findStringEnd(json: []const u8, start: usize) ?usize {
    var i = start;
    var escaped = false;
    while (i < json.len) {
        if (escaped) {
            escaped = false;
            i += 1;
            continue;
        }
        if (json[i] == '\\') {
            escaped = true;
            i += 1;
            continue;
        }
        if (json[i] == '"') {
            return i;
        }
        // Handle UTF-8 multi-byte characters including emojis
        const byte = json[i];
        if (byte < 0x80) {
            i += 1;
        } else if (byte < 0xE0) {
            i += 2;
        } else if (byte < 0xF0) {
            i += 3;
        } else {
            i += 4;
        }
    }
    return null;
}
