const std = @import("std");
const ws = @import("ws.zig");
const Event = @import("event.zig").Event;
const json = @import("json.zig");

pub const RelayConnection = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    ws_client: ws.WebSocketClient,
    read: bool = true,
    write: bool = true,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) RelayConnection {
        return .{
            .allocator = allocator,
            .url = url,
            .ws_client = ws.WebSocketClient.init(allocator, url),
        };
    }

    pub fn connect(self: *RelayConnection) !void {
        try self.ws_client.connect();
        self.connected = true;
    }

    pub fn disconnect(self: *RelayConnection) void {
        self.ws_client.disconnect();
        self.connected = false;
    }

    pub fn sendEvent(self: *RelayConnection, event: Event) !void {
        const msg = try json.serialize(self.allocator, .{ "EVENT", event });
        defer self.allocator.free(msg);
        try self.ws_client.send(msg);
    }

    pub fn subscribe(self: *RelayConnection, sub_id: []const u8, filters: anytype) !void {
        const msg = try json.serialize(self.allocator, .{ "REQ", sub_id, filters });
        defer self.allocator.free(msg);
        try self.ws_client.send(msg);
    }

    pub fn closeSubscription(self: *RelayConnection, sub_id: []const u8) !void {
        const msg = try json.serialize(self.allocator, .{ "CLOSE", sub_id });
        defer self.allocator.free(msg);
        try self.ws_client.send(msg);
    }
};

pub const RelayPool = struct {
    allocator: std.mem.Allocator,
    relays: std.ArrayList(RelayConnection),

    pub fn init(allocator: std.mem.Allocator) RelayPool {
        return .{
            .allocator = allocator,
            .relays = std.ArrayList(RelayConnection).init(allocator),
        };
    }

    pub fn deinit(self: *RelayPool) void {
        for (self.relays.items) |*relay| {
            relay.disconnect();
        }
        self.relays.deinit();
    }

    pub fn addRelay(self: *RelayPool, url: []const u8) !void {
        const relay = RelayConnection.init(self.allocator, url);
        try self.relays.append(relay);
    }

    pub fn connectAll(self: *RelayPool) !void {
        for (self.relays.items) |*relay| {
            relay.connect() catch |err| {
                std.debug.print("Failed to connect to {s}: {}\n", .{ relay.url, err });
            };
        }
    }

    pub fn broadcast(self: *RelayPool, event: Event) !void {
        for (self.relays.items) |*relay| {
            if (relay.connected and relay.write) {
                relay.sendEvent(event) catch |err| {
                    std.debug.print("Failed to send to {s}: {}\n", .{ relay.url, err });
                };
            }
        }
    }
};
