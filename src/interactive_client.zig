const std = @import("std");
const NostrWsClient = @import("nostr_ws_client.zig").NostrWsClient;
const nostr_crypto = @import("nostr_crypto.zig");

pub const InteractiveClient = struct {
    allocator: std.mem.Allocator,
    relays: std.ArrayList(NostrWsClient),
    channel: []const u8,
    running: std.atomic.Value(bool),
    keypair: nostr_crypto.KeyPair,
    username: []const u8,
    last_sent_ids: [2][64]u8 = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: []const u8, primary_relay: []const u8) Self {
        // Ask for username
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        stdout.print("Enter your username: ", .{}) catch {};
        var username_buf: [64]u8 = undefined;
        var username: []const u8 = "anon";
        if (stdin.readUntilDelimiterOrEof(&username_buf, '\n') catch null) |input| {
            const trimmed = std.mem.trim(u8, input, " \t\r\n");
            if (trimmed.len > 0) {
                username = allocator.dupe(u8, trimmed) catch "anon";
            }
        }

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
        std.debug.print("Public key: {s}\n", .{std.fmt.fmtSliceHexLower(&keypair.public_key)});

        // Load geohash-specific relays
        var relays = std.ArrayList(NostrWsClient).init(allocator);
        
        // First, try to load geohash-specific relays
        const geohash_relay_file = std.fs.cwd().openFile("assets/geohash-relays.json", .{}) catch null;
        var loaded_from_geohash = false;
        
        if (geohash_relay_file) |file| {
            defer file.close();
            const content = file.readToEndAlloc(allocator, 1024 * 1024) catch null;
            if (content) |data| {
                defer allocator.free(data);
                
                // Simple JSON parsing for geohash relay mapping
                // Look for exact match first (e.g., "9q")
                const search_key = std.fmt.allocPrint(allocator, "\"{s}\":", .{channel}) catch null;
                if (search_key) |key| {
                    defer allocator.free(key);
                    if (std.mem.indexOf(u8, data, key)) |start_idx| {
                        // Found exact geohash match, extract relay URLs
                        if (std.mem.indexOf(u8, data[start_idx..], "[")) |bracket_start| {
                            const abs_start = start_idx + bracket_start;
                            if (std.mem.indexOf(u8, data[abs_start..], "]")) |bracket_end| {
                                const relay_array = data[abs_start + 1 .. abs_start + bracket_end];
                                var relay_iter = std.mem.tokenizeAny(u8, relay_array, ",");
                                while (relay_iter.next()) |relay_entry| {
                                    // Extract URL from quoted string
                                    var trimmed = std.mem.trim(u8, relay_entry, " \t\n\r");
                                    if (trimmed.len > 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
                                        const url = trimmed[1 .. trimmed.len - 1];
                                        relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, url) catch url)) catch continue;
                                        loaded_from_geohash = true;
                                    }
                                }
                            }
                        }
                    }
                }
                
                // If no exact match, try prefix match (e.g., "9" for "9q")
                if (!loaded_from_geohash and channel.len > 0) {
                    const prefix_key = std.fmt.allocPrint(allocator, "\"{c}\":", .{channel[0]}) catch null;
                    if (prefix_key) |key| {
                        defer allocator.free(key);
                        if (std.mem.indexOf(u8, data, key)) |start_idx| {
                            if (std.mem.indexOf(u8, data[start_idx..], "[")) |bracket_start| {
                                const abs_start = start_idx + bracket_start;
                                if (std.mem.indexOf(u8, data[abs_start..], "]")) |bracket_end| {
                                    const relay_array = data[abs_start + 1 .. abs_start + bracket_end];
                                    var relay_iter = std.mem.tokenizeAny(u8, relay_array, ",");
                                    while (relay_iter.next()) |relay_entry| {
                                        var trimmed = std.mem.trim(u8, relay_entry, " \t\n\r");
                                        if (trimmed.len > 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
                                            const url = trimmed[1 .. trimmed.len - 1];
                                            relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, url) catch url)) catch continue;
                                            loaded_from_geohash = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // If no geohash-specific relays found, fall back to default relays
        if (!loaded_from_geohash) {
            const relay_file = std.fs.cwd().openFile("assets/default-relays.txt", .{}) catch null;
            if (relay_file) |file| {
                defer file.close();
                const content = file.readToEndAlloc(allocator, 1024 * 1024) catch null;
                if (content) |data| {
                    defer allocator.free(data);
                    var lines = std.mem.tokenizeAny(u8, data, "\n\r");
                    var count: usize = 0;
                    while (lines.next()) |line| {
                        const trimmed = std.mem.trim(u8, line, " \t");
                        if (trimmed.len > 0 and count < 5) { // Use first 5 relays
                            relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, trimmed) catch trimmed)) catch continue;
                            count += 1;
                        }
                    }
                }
            }
        }
        
        // If still no relays loaded, use hardcoded defaults
        if (relays.items.len == 0) {
            // Always add primary relay
            relays.append(NostrWsClient.init(allocator, primary_relay)) catch {};
            
            // Add some default relays
            const default_relays = [_][]const u8{
                "wss://relay.wellorder.net",
                "wss://nostr-pub.wellorder.net",
                "wss://relay.damus.io",
                "wss://nos.lol",
            };
            
            for (default_relays) |relay| {
                if (!std.mem.eql(u8, relay, primary_relay)) {
                    relays.append(NostrWsClient.init(allocator, relay)) catch continue;
                }
            }
        }
        
        if (loaded_from_geohash) {
            std.debug.print("Loaded {} geohash-specific relays for '{s}'\n", .{ relays.items.len, channel });
        } else {
            std.debug.print("Loaded {} default relays\n", .{relays.items.len});
        }
        
        var client = Self{
            .allocator = allocator,
            .relays = relays,
            .channel = channel,
            .running = std.atomic.Value(bool).init(true),
            .keypair = keypair,
            .username = username,
            .last_sent_ids = undefined,
        };
        
        // Initialize last_sent_ids
        @memset(&client.last_sent_ids[0], 0);
        @memset(&client.last_sent_ids[1], 0);
        
        return client;
    }

    pub fn start(self: *Self) !void {
        // Connect to all relays in parallel
        for (self.relays.items) |*relay| {
            relay.connect() catch |err| {
                std.debug.print("Warning: Could not connect to relay {s}: {}\n", .{ relay.url, err });
                continue;
            };
            
            // Subscribe to both kind 1 and 20000 messages with #g geotag
            relay.subscribeToChannelSmart(self.channel) catch |err| {
                std.debug.print("Warning: Could not subscribe on relay {s}: {}\n", .{ relay.url, err });
            };
        }

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
            // Try to receive from all relays
            for (self.relays.items) |*relay| {
                const msg = relay.receiveMessage() catch |err| {
                    if (self.running.load(.monotonic) and err != error.WouldBlock) {
                        // Only log non-WouldBlock errors
                    }
                    continue;
                };

                const message = msg orelse continue;
                defer message.deinit();

            switch (message.type) {
                .EVENT => {
                    if (message.content) |content| {
                        // Check if this is our own event coming back
                        var is_our_echo = false;
                        if (message.id) |msg_id| {
                            for (self.last_sent_ids) |sent_id| {
                                if (std.mem.eql(u8, msg_id, &sent_id)) {
                                    is_our_echo = true;
                                    break;
                                }
                            }
                        }
                        
                        // Try to extract nickname from tags
                        var nickname: ?[]const u8 = null;
                        if (message.tags) |tags| {
                            if (tags.len >= 2 and std.mem.eql(u8, tags[0], "n")) {
                                // Check if nickname is not empty
                                if (tags[1].len > 0) {
                                    nickname = tags[1];
                                }
                            }
                        }

                        const display_name = if (nickname) |n| n else blk: {
                            // Fallback to first 8 chars of pubkey if no nickname
                            const author_hex = if (message.author) |author| blk2: {
                                if (author.len >= 8) {
                                    break :blk2 author[0..8];
                                } else if (author.len > 0) {
                                    break :blk2 author;
                                } else {
                                    break :blk2 "anon";
                                }
                            } else "anon";
                            break :blk author_hex;
                        };

                        if (is_our_echo) {
                            // Our message echoed back - validation!
                            std.debug.print("\r🔄 [{s}] Echo confirmed\n", .{relay.url});
                        }
                        
                        if (message.author) |author| {
                            const our_pubkey_hex = std.fmt.fmtSliceHexLower(&self.keypair.public_key);
                            var our_pubkey_buf: [64]u8 = undefined;
                            _ = std.fmt.bufPrint(&our_pubkey_buf, "{}", .{our_pubkey_hex}) catch {};
                            
                            if (!std.mem.eql(u8, author, &our_pubkey_buf)) {
                                // Only show "Received from" for others' messages
                                std.debug.print("\r[From: {s}]\n", .{author[0..8]});
                            }
                        }

                        // Clear current line, print message, restore prompt
                        const prefix = if (is_our_echo) "[You]" else display_name;
                        std.debug.print("\r{s: <50}\r[{s}]: {s}\n> ", .{ " ", prefix, content });
                    }
                },
                .EOSE => {
                    std.debug.print("\r--- Ready for real-time messages ---\n> ", .{});
                },
                .NOTICE => {
                    if (message.content) |content| {
                        std.debug.print("\rNOTICE: {s}\n> ", .{content});
                    }
                },
                .OK => {
                    // Enhanced OK response tracking
                    const symbol = if (message.ok_status orelse false) "✅" else "❌";
                    
                    if (message.event_id) |eid| {
                        // Check if this is one of our recent events
                        var is_ours = false;
                        for (self.last_sent_ids) |sent_id| {
                            if (std.mem.eql(u8, eid, &sent_id)) {
                                is_ours = true;
                                break;
                            }
                        }
                        
                        if (is_ours) {
                            if (message.ok_status orelse false) {
                                std.debug.print("\r{s} [{s}] Accepted our event\n> ", .{ symbol, relay.url });
                            } else {
                                const reason = message.content orelse "unknown reason";
                                std.debug.print("\r{s} [{s}] Rejected: {s}\n> ", .{ symbol, relay.url, reason });
                            }
                        } else {
                            // Not our event, less verbose
                            if (!(message.ok_status orelse false)) {
                                std.debug.print("\r{s} [{s}] Event rejected\n> ", .{ symbol, relay.url });
                            }
                        }
                    } else {
                        std.debug.print("\r[{s}] OK status: {}\n> ", .{ relay.url, message.ok_status orelse false });
                    }
                },
                .AUTH => {
                    // Handle AUTH challenge
                    if (message.content) |challenge| {
                        std.debug.print("\r[{s}] AUTH challenge received: {s}\n> ", .{ relay.url, challenge });
                        self.handleAuth(relay, challenge) catch |err| {
                            std.debug.print("\r[{s}] Failed to handle AUTH: {}\n> ", .{ relay.url, err });
                        };
                    }
                },
                else => {},
            }
            }
            
            // Small sleep after checking all relays
            std.time.sleep(1_000_000); // 1ms
        }
    }

    fn handleAuth(self: *Self, relay: *NostrWsClient, challenge: []const u8) !void {
        // Create AUTH event according to NIP-42
        // kind: 22242, tags: [["relay", relay_url], ["challenge", challenge]]
        const tags = [_][]const []const u8{
            &[_][]const u8{ "relay", relay.url },
            &[_][]const u8{ "challenge", challenge },
        };

        // Create AUTH event (kind 22242)
        var auth_event = try nostr_crypto.NostrEvent.create(
            self.keypair,
            22242, // AUTH event kind
            &tags,
            "",
            self.allocator
        );

        // Convert to JSON
        const auth_json = try auth_event.toJson(self.allocator);
        defer self.allocator.free(auth_json);

        // Send AUTH response
        var command_buffer: [4096]u8 = undefined;
        const command = try std.fmt.bufPrint(&command_buffer, "[\"AUTH\",{s}]", .{auth_json});

        if (relay.is_tls) {
            try relay.tls_client.?.sendText(command);
        } else {
            try relay.ws_client.?.sendText(command);
        }
        
        std.debug.print("[{s}] AUTH response sent\n", .{relay.url});
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
        // Create proper tags for geohash with #g tag and nickname
        const tags = [_][]const []const u8{
            &[_][]const u8{ "g", self.channel },
            &[_][]const u8{ "n", self.username },
        };

        // Create both kind 20000 and kind 1 events
        var event_kind20000 = try nostr_crypto.NostrEvent.create(self.keypair, 20000, &tags, content, self.allocator);
        var event_kind1 = try nostr_crypto.NostrEvent.create(self.keypair, 1, &tags, content, self.allocator);

        // Convert events to JSON
        const event20000_json = try event_kind20000.toJson(self.allocator);
        defer self.allocator.free(event20000_json);
        const event1_json = try event_kind1.toJson(self.allocator);
        defer self.allocator.free(event1_json);

        // Create EVENT commands
        var command20000_buffer: [4096]u8 = undefined;
        const command20000 = try std.fmt.bufPrint(&command20000_buffer, "[\"EVENT\",{s}]", .{event20000_json});
        var command1_buffer: [4096]u8 = undefined;
        const command1 = try std.fmt.bufPrint(&command1_buffer, "[\"EVENT\",{s}]", .{event1_json});

        std.debug.print("\n[DUAL-POST] Sending to {} relays...\n", .{self.relays.items.len});
        std.debug.print("Sending: {s}\n", .{command20000});
        std.debug.print("Sending: {s}\n", .{command1});

        // Send both events to all relays in parallel
        var sent_count: usize = 0;
        for (self.relays.items) |*relay| {
            // Skip read-only relays
            if (!relay.can_write) {
                std.debug.print("[{s}] Skipping (read-only relay)\n", .{relay.url});
                continue;
            }
            
            // Send kind 20000
            if (relay.is_tls) {
                relay.tls_client.?.sendText(command20000) catch |err| {
                    std.debug.print("[{s}] ❌ Failed kind 20000: {}\n", .{ relay.url, err });
                    continue;
                };
            } else {
                relay.ws_client.?.sendText(command20000) catch |err| {
                    std.debug.print("[{s}] ❌ Failed kind 20000: {}\n", .{ relay.url, err });
                    continue;
                };
            }
            
            // Send kind 1
            if (relay.is_tls) {
                relay.tls_client.?.sendText(command1) catch |err| {
                    std.debug.print("[{s}] ❌ Failed kind 1: {}\n", .{ relay.url, err });
                    continue;
                };
            } else {
                relay.ws_client.?.sendText(command1) catch |err| {
                    std.debug.print("[{s}] ❌ Failed kind 1: {}\n", .{ relay.url, err });
                    continue;
                };
            }
            
            std.debug.print("[{s}] ✓ Sent both kinds\n", .{relay.url});
            sent_count += 1;
        }
        
        std.debug.print("\n📤 Published to {}/{} relays\n", .{ sent_count, self.relays.items.len });
        std.debug.print("Event IDs: kind20000={s}, kind1={s}\n", .{ event_kind20000.id, event_kind1.id });
        
        // Store our event IDs to track when they come back
        self.last_sent_ids[0] = event_kind20000.id;
        self.last_sent_ids[1] = event_kind1.id;
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .monotonic);
        if (!std.mem.eql(u8, self.username, "anon")) {
            self.allocator.free(self.username);
        }
        
        // Clean up all relay clients
        for (self.relays.items) |*relay| {
            relay.deinit();
        }
        self.relays.deinit();
    }
};
