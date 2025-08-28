const std = @import("std");
const net = std.net;
const http = std.http;

pub const SimpleNostrClient = struct {
    allocator: std.mem.Allocator,
    relay_url: []const u8,
    client: http.Client,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator, relay_url: []const u8) SimpleNostrClient {
        return .{
            .allocator = allocator,
            .relay_url = relay_url,
            .client = http.Client{ .allocator = allocator },
            .connected = false,
        };
    }

    pub fn deinit(self: *SimpleNostrClient) void {
        self.client.deinit();
    }

    // For testing - just print what we would do
    pub fn connect(self: *SimpleNostrClient) !void {
        std.debug.print("[CONNECT] Would connect to: {s}\n", .{self.relay_url});
        self.connected = true;
    }

    pub fn subscribeToChannel(self: *SimpleNostrClient, channel: []const u8) !void {
        if (!self.connected) return error.NotConnected;

        // Format subscription request
        var req_buffer: [512]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buffer,
            \\["REQ","1",{{"kinds":[1],"#t":["{s}"],"limit":50}}]
        , .{channel});

        std.debug.print("[SUBSCRIBE] Would send: {s}\n", .{req});
    }

    pub fn simulateMessages(self: *SimpleNostrClient, channel: []const u8) !void {
        _ = self;

        // Print welcome message
        std.debug.print("[MSG] Welcome to the #{s} channel!\n", .{channel});
        std.time.sleep(1 * std.time.ns_per_s);

        // Simulate receiving messages
        const messages = [_][]const u8{
            "This is a test message streaming in...",
            "Nostr is a decentralized protocol",
            "Messages are signed and verified",
            "Anyone can run a relay",
            "Clients connect via WebSocket",
            "Using cryptographic signatures for identity",
            "No central authority needed",
            "Resistant to censorship",
            "Join the conversation!",
        };

        for (messages) |msg| {
            std.debug.print("[MSG] {s}\n", .{msg});
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }
};
