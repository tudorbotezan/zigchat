const std = @import("std");

pub const WebSocketClient = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) WebSocketClient {
        return .{
            .allocator = allocator,
            .url = url,
        };
    }

    pub fn connect(self: *WebSocketClient) !void {
        _ = self;
        std.debug.print("TODO: WebSocket connect implementation\n", .{});
    }

    pub fn disconnect(self: *WebSocketClient) void {
        self.connected = false;
    }

    pub fn send(self: *WebSocketClient, data: []const u8) !void {
        _ = self;
        _ = data;
        std.debug.print("TODO: WebSocket send implementation\n", .{});
    }

    pub fn receive(self: *WebSocketClient) ![]u8 {
        _ = self;
        return error.NotImplemented;
    }
};
