const std = @import("std");
const websocket = @import("websocket");

pub const NostrClient = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    client: ?*websocket.Client = null,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) NostrClient {
        return .{
            .allocator = allocator,
            .url = url,
        };
    }

    pub fn connect(self: *NostrClient) !void {
        self.client = try websocket.connect(self.allocator, self.url, &.{});
        self.connected = true;
        std.debug.print("Connected to: {s}\n", .{self.url});
    }

    pub fn disconnect(self: *NostrClient) void {
        if (self.client) |client| {
            client.close();
            self.client = null;
        }
        self.connected = false;
    }

    pub fn send(self: *NostrClient, data: []const u8) !void {
        if (!self.connected or self.client == null) return error.NotConnected;
        try self.client.?.write(data);
        // Don't print sent messages - let higher level code handle that
    }

    pub fn receive(self: *NostrClient) ![]u8 {
        if (!self.connected or self.client == null) return error.NotConnected;

        const msg = try self.client.?.read();
        defer msg.deinit();

        return try self.allocator.dupe(u8, msg.data);
    }

    pub fn receiveTimeout(self: *NostrClient, timeout_ms: u32) !?[]u8 {
        if (!self.connected or self.client == null) return error.NotConnected;

        const msg = try self.client.?.readTimeout(timeout_ms) orelse return null;
        defer msg.deinit();

        return try self.allocator.dupe(u8, msg.data);
    }

    pub fn deinit(self: *NostrClient) void {
        self.disconnect();
    }
};
