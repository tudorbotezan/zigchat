const std = @import("std");
const WebSocketClient = @import("websocket_client.zig").WebSocketClient;
const TlsWebSocketClient = @import("websocket_tls.zig").TlsWebSocketClient;

pub const NostrWsClient = struct {
    allocator: std.mem.Allocator,
    ws_client: ?WebSocketClient = null,
    tls_client: ?TlsWebSocketClient = null,
    subscription_id: []const u8 = "1",
    is_tls: bool,
    url: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, relay_url: []const u8) Self {
        const is_tls = std.mem.startsWith(u8, relay_url, "wss://");

        return .{
            .allocator = allocator,
            .is_tls = is_tls,
            .url = relay_url,
        };
    }

    pub fn connect(self: *Self) !void {
        if (self.is_tls) {
            self.tls_client = TlsWebSocketClient.init(self.allocator, self.url);
            try self.tls_client.?.connect();
        } else {
            self.ws_client = WebSocketClient.init(self.allocator, self.url);
            try self.ws_client.?.connect();
        }
        std.debug.print("Connected to Nostr relay\n", .{});
    }

    pub fn subscribeToChannel(self: *Self, channel: []const u8) !void {
        // Create REQ message for channel subscription
        // For geohash channels, subscribe to both kind 1 and 20000 with #g tag
        // Format: ["REQ", "subscription_id", {"kinds": [1,20000], "#g": ["geohash"], "limit": 100}]
        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","{s}",{{"kinds":[1,20000],"#g":["{s}"],"limit":100}}]
        , .{ self.subscription_id, channel });

        if (self.is_tls) {
            try self.tls_client.?.sendText(req);
        } else {
            try self.ws_client.?.sendText(req);
        }
        std.debug.print("Subscribed to geohash: {s}\n", .{channel});
    }

    pub fn subscribeToGlobal(self: *Self) !void {
        // Subscribe to all kind 1 (text notes) messages
        var req_buffer: [256]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","{s}",{{"kinds":[1],"limit":50}}]
        , .{self.subscription_id});

        if (self.is_tls) {
            try self.tls_client.?.sendText(req);
        } else {
            try self.ws_client.?.sendText(req);
        }
        std.debug.print("Subscribed to global feed\n", .{});
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

        // Debug: log raw messages to see relay responses
        if (std.mem.startsWith(u8, raw_msg, "[\"OK\"")) {
            std.debug.print("\n[RELAY RAW]: {s}\n", .{raw_msg});
        }

        return try parseNostrMessage(self.allocator, raw_msg);
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
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const NostrMessage) void {
        if (self.content) |content| self.allocator.free(content);
        if (self.author) |author| self.allocator.free(author);
        if (self.id) |id| self.allocator.free(id);
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

    if (std.mem.startsWith(u8, json_str, "[\"EVENT\"")) {
        msg_type = .EVENT;

        // Extract content field
        if (findJsonString(json_str, "\"content\":\"")) |content_start| {
            const end = findStringEnd(json_str, content_start) orelse json_str.len;
            content = try allocator.dupe(u8, json_str[content_start..end]);
        }

        // Extract pubkey (author)
        if (findJsonString(json_str, "\"pubkey\":\"")) |pubkey_start| {
            const end = findStringEnd(json_str, pubkey_start) orelse json_str.len;
            author = try allocator.dupe(u8, json_str[pubkey_start..end]);
        }

        // Extract created_at
        if (std.mem.indexOf(u8, json_str, "\"created_at\":")) |created_at_pos| {
            const start = created_at_pos + "\"created_at\":".len;
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
    } else if (std.mem.startsWith(u8, json_str, "[\"AUTH\"")) {
        msg_type = .AUTH;
    }

    return NostrMessage{
        .type = msg_type,
        .content = content,
        .author = author,
        .created_at = created_at,
        .allocator = allocator,
    };
}

fn findJsonString(json: []const u8, marker: []const u8) ?usize {
    if (std.mem.indexOf(u8, json, marker)) |pos| {
        return pos + marker.len;
    }
    return null;
}

fn findStringEnd(json: []const u8, start: usize) ?usize {
    var i = start;
    var escaped = false;
    while (i < json.len) : (i += 1) {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (json[i] == '\\') {
            escaped = true;
            continue;
        }
        if (json[i] == '"') {
            return i;
        }
    }
    return null;
}
