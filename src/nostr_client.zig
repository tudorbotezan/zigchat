const std = @import("std");
const websocket = @import("websocket");

pub const NostrClient = struct {
    allocator: std.mem.Allocator,
    relay_url: []const u8,
    client: ?*websocket.Client = null,
    connected: bool = false,
    subscription_id: []const u8 = "1",

    pub fn init(allocator: std.mem.Allocator, relay_url: []const u8) NostrClient {
        return .{
            .allocator = allocator,
            .relay_url = relay_url,
        };
    }

    pub fn connect(self: *NostrClient) !void {
        const uri = try std.Uri.parse(self.relay_url);
        const host = uri.host orelse return error.InvalidUrl;
        const port = uri.port orelse 443;

        self.client = try websocket.Client.init(self.allocator, .{
            .port = port,
            .host = host,
            .tls = true,
        });

        const path = uri.path orelse "/";
        try self.client.?.handshake(path, .{
            .timeout_ms = 10000,
            .headers = "User-Agent: bitchat/0.1.0",
        });

        self.connected = true;
        std.debug.print("Connected to {s}\n", .{self.relay_url});
    }

    pub fn disconnect(self: *NostrClient) void {
        if (self.client) |client| {
            client.close() catch {};
            client.deinit();
            self.client = null;
        }
        self.connected = false;
    }

    pub fn subscribeToGlobalFeed(self: *NostrClient) !void {
        if (!self.connected) return error.NotConnected;

        // Create subscription message for global feed (kind 1 = text notes)
        // ["REQ", "subscription_id", {"kinds": [1], "limit": 100}]
        const req =
            \\["REQ","1",{"kinds":[1],"limit":100}]
        ;

        try self.client.?.write(req);
        std.debug.print("Subscribed to global feed\n", .{});
    }

    pub fn subscribeToChannel(self: *NostrClient, channel: []const u8) !void {
        if (!self.connected) return error.NotConnected;

        // Subscribe to messages with a specific hashtag
        // ["REQ", "subscription_id", {"kinds": [1], "#t": ["channel_name"], "limit": 100}]
        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","1",{{"kinds":[1],"#t":["{s}"],"limit":100}}]
        , .{channel});

        try self.client.?.write(req);
        std.debug.print("Subscribed to channel: {s}\n", .{channel});
    }

    pub fn receiveMessage(self: *NostrClient) !?[]u8 {
        if (!self.connected or self.client == null) return error.NotConnected;

        const msg = self.client.?.read() catch |err| {
            if (err == error.WouldBlock) return null;
            return err;
        };
        defer msg.deinit();

        const data = try self.allocator.dupe(u8, msg.data);
        return data;
    }

    pub fn receiveMessageTimeout(self: *NostrClient, timeout_ms: u32) !?[]u8 {
        if (!self.connected or self.client == null) return error.NotConnected;

        const msg = self.client.?.readTimeout(timeout_ms) catch |err| {
            if (err == error.Timeout) return null;
            return err;
        };
        defer msg.deinit();

        if (msg.data.len == 0) return null;

        const data = try self.allocator.dupe(u8, msg.data);
        return data;
    }

    pub fn deinit(self: *NostrClient) void {
        self.disconnect();
    }
};
