const std = @import("std");
const NostrWsClient = @import("nostr_ws_client.zig").NostrWsClient;
const nostr_crypto = @import("nostr_crypto.zig");

pub const InteractiveClient = struct {
    allocator: std.mem.Allocator,
    client: NostrWsClient,
    channel: []const u8,
    running: std.atomic.Value(bool),
    keypair: nostr_crypto.KeyPair,
    username: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: []const u8, relay_url: []const u8) Self {
        // Generate a keypair for this session
        const keypair = nostr_crypto.KeyPair.generate() catch blk: {
            std.debug.print("Failed to generate keypair, using test keypair\n", .{});
            // Fallback to a known test keypair
            var test_keypair: nostr_crypto.KeyPair = undefined;
            @memset(&test_keypair.private_key, 0);
            test_keypair.private_key[31] = 1;
            const pubkey_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
            _ = std.fmt.hexToBytes(&test_keypair.public_key, pubkey_hex) catch unreachable;
            break :blk test_keypair;
        };

        std.debug.print("Generated keypair for this session\n", .{});
        std.debug.print("Public key: {}\n", .{std.fmt.fmtSliceHexLower(&keypair.public_key)});

        return .{
            .allocator = allocator,
            .client = NostrWsClient.init(allocator, relay_url),
            .channel = channel,
            .running = std.atomic.Value(bool).init(true),
            .keypair = keypair,
            .username = "11111",
        };
    }

    pub fn start(self: *Self) !void {
        try self.client.connect();
        try self.client.subscribeToChannel(self.channel);

        std.debug.print("\n=== Bitchat Interactive Mode ===\n", .{});
        std.debug.print("Username: {s}\n", .{self.username});
        std.debug.print("Geohash: {s}\n", .{self.channel});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  Type a message and press Enter to send\n", .{});
        std.debug.print("  /quit or Ctrl-C to exit\n", .{});
        std.debug.print("{s}\n\n", .{"-" ** 50});

        // Start receive thread
        const recv_thread = try std.Thread.spawn(.{}, receiveLoop, .{self});

        // Handle input in main thread
        try self.inputLoop();

        // Cleanup
        self.running.store(false, .monotonic);
        recv_thread.join();
    }

    fn receiveLoop(self: *Self) void {
        while (self.running.load(.monotonic)) {
            const msg = self.client.receiveMessage() catch |err| {
                if (self.running.load(.monotonic)) {
                    std.debug.print("\rError receiving: {}\n> ", .{err});
                }
                std.time.sleep(100_000_000); // 100ms
                continue;
            };

            if (msg) |message| {
                defer message.deinit();

                switch (message.type) {
                    .EVENT => {
                        if (message.content) |content| {
                            const author_hex = if (message.author) |author|
                                if (author.len > 8) author[0..8] else author
                            else
                                "00000000";

                            // Generate a visual name from the hex (use first 4 chars as seed)
                            const visual_names = [_][]const u8{ "Alice", "Bob", "Charlie", "David", "Eve", "Frank", "Grace", "Heidi", "Ivan", "Judy", "Kevin", "Laura", "Mike", "Nancy", "Oscar", "Peggy" };
                            var name_index: usize = 0;
                            if (message.author) |author| {
                                // Use first byte of pubkey to pick a name
                                if (author.len >= 2) {
                                    const byte = std.fmt.parseInt(u8, author[0..2], 16) catch 0;
                                    name_index = byte % visual_names.len;
                                }
                            }
                            const visual_name = visual_names[name_index];

                            // Clear current line, print message, restore prompt
                            std.debug.print("\r{s: <50}\r[{s}:{s}]: {s}\n> ", .{ " ", visual_name, author_hex, content });
                        }
                    },
                    .EOSE => {
                        std.debug.print("\r--- End of stored events ---\n> ", .{});
                    },
                    .NOTICE => {
                        if (message.content) |content| {
                            std.debug.print("\rNOTICE: {s}\n> ", .{content});
                        }
                    },
                    else => {},
                }
            }

            std.time.sleep(10_000_000); // 10ms
        }
    }

    fn inputLoop(self: *Self) !void {
        const stdin = std.io.getStdIn().reader();
        var buf: [1024]u8 = undefined;

        while (self.running.load(.monotonic)) {
            std.debug.print("> ", .{});

            if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\r\n");

                if (trimmed.len == 0) continue;

                if (std.mem.eql(u8, trimmed, "/quit")) {
                    std.debug.print("Goodbye!\n", .{});
                    break;
                }

                // Send message
                try self.sendMessage(trimmed);
                std.debug.print("Sent: {s}\n", .{trimmed});
            } else {
                // EOF (Ctrl-D)
                break;
            }
        }

        self.running.store(false, .monotonic);
    }

    fn sendMessage(self: *Self, content: []const u8) !void {
        // Just send the raw content without username prefix
        const formatted_content = content;

        // Create proper tags for geohash
        const tags = [_][]const []const u8{
            &[_][]const u8{ "g", self.channel },
        };

        // Create a proper Nostr event - use kind 20000 for ephemeral/channel messages
        var event = try nostr_crypto.NostrEvent.create(self.keypair, 20000, // kind 20000 for ephemeral channel messages
            &tags, formatted_content, self.allocator);

        // Convert event to JSON
        const event_json = try event.toJson(self.allocator);
        defer self.allocator.free(event_json);

        // Create the EVENT command
        var command_buffer: [4096]u8 = undefined;
        const command = try std.fmt.bufPrint(&command_buffer, "[\"EVENT\",{s}]", .{event_json});

        // Send to relay
        if (self.client.is_tls) {
            try self.client.tls_client.?.sendText(command);
        } else {
            try self.client.ws_client.?.sendText(command);
        }

        std.debug.print("Debug: Sent event with id: {s}\n", .{event.id});
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .monotonic);
        self.client.deinit();
    }
};
