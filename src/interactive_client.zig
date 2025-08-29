const std = @import("std");
const NostrWsClient = @import("nostr_ws_client.zig").NostrWsClient;
const nostr_crypto = @import("nostr_crypto.zig");
const MessageQueue = @import("message_queue.zig").MessageQueue;

pub const InteractiveClient = struct {
    allocator: std.mem.Allocator,
    relays: std.ArrayList(NostrWsClient),
    relay_threads: std.ArrayList(std.Thread),
    message_queue: MessageQueue,
    channel: []const u8,
    running: std.atomic.Value(bool),
    keypair: nostr_crypto.KeyPair,
    username: []const u8,
    last_sent_ids: [2][64]u8 = undefined,
    debug_mode: bool = false,
    seen_events: std.hash_map.StringHashMap(void), // Track seen event IDs for deduplication
    seen_mutex: std.Thread.Mutex,
    known_users: std.hash_map.StringHashMap([]const u8), // Map of pubkey -> nickname
    users_mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: []const u8, primary_relay: []const u8, debug_mode: bool) Self {
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

        // Only show in debug mode
        if (debug_mode) {
            std.debug.print("Generated keypair for this session\n", .{});
            std.debug.print("Public key: {s}\n", .{std.fmt.fmtSliceHexLower(&keypair.public_key)});
        }

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
                                        relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, url) catch url, debug_mode)) catch continue;
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
                                            relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, url) catch url, debug_mode)) catch continue;
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
                            relays.append(NostrWsClient.init(allocator, allocator.dupe(u8, trimmed) catch trimmed, debug_mode)) catch continue;
                            count += 1;
                        }
                    }
                }
            }
        }
        
        // If still no relays loaded, use hardcoded defaults
        if (relays.items.len == 0) {
            // Always add primary relay
            relays.append(NostrWsClient.init(allocator, primary_relay, debug_mode)) catch {};
            
            // Add some default relays
            const default_relays = [_][]const u8{
                "wss://relay.wellorder.net",
                "wss://nostr-pub.wellorder.net",
                "wss://relay.damus.io",
                "wss://nos.lol",
            };
            
            for (default_relays) |relay| {
                if (!std.mem.eql(u8, relay, primary_relay)) {
                    relays.append(NostrWsClient.init(allocator, relay, debug_mode)) catch continue;
                }
            }
        }
        
        if (debug_mode) {
            if (loaded_from_geohash) {
                std.debug.print("Loaded {} geohash-specific relays for '{s}'\n", .{ relays.items.len, channel });
            } else {
                std.debug.print("Loaded {} default relays\n", .{relays.items.len});
            }
        }
        
        var client = Self{
            .allocator = allocator,
            .relays = relays,
            .relay_threads = std.ArrayList(std.Thread).init(allocator),
            .message_queue = MessageQueue.init(allocator),
            .channel = channel,
            .running = std.atomic.Value(bool).init(true),
            .keypair = keypair,
            .username = username,
            .last_sent_ids = undefined,
            .debug_mode = debug_mode,
            .seen_events = std.hash_map.StringHashMap(void).init(allocator),
            .seen_mutex = .{},
            .known_users = std.hash_map.StringHashMap([]const u8).init(allocator),
            .users_mutex = .{},
        };
        
        // Initialize last_sent_ids
        @memset(&client.last_sent_ids[0], 0);
        @memset(&client.last_sent_ids[1], 0);
        
        return client;
    }

    pub fn start(self: *Self) !void {
        // Connect to all relays and spawn threads
        for (self.relays.items, 0..) |*relay, idx| {
            relay.connect() catch |err| {
                if (self.debug_mode) {
                    std.debug.print("Warning: Could not connect to relay {s}: {}\n", .{ relay.url, err });
                }
                continue;
            };
            
            // Subscribe to both kind 1 and 20000 messages with #g geotag
            relay.subscribeToChannelSmart(self.channel, self.debug_mode) catch |err| {
                if (self.debug_mode) {
                    std.debug.print("Warning: Could not subscribe on relay {s}: {}\n", .{ relay.url, err });
                }
            };
            
            // Spawn dedicated thread for this relay
            const thread = try std.Thread.spawn(.{}, relayReceiveLoop, .{ self, idx });
            try self.relay_threads.append(thread);
        }

        std.debug.print("\n=== Zigchat Interactive Mode ===\n", .{});
        std.debug.print("Username: {s}\n", .{self.username});
        std.debug.print("Geohash: {s}\n", .{self.channel});
        std.debug.print("Connected to {} relays\n", .{self.relay_threads.items.len});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  Type a message and press Enter to send\n", .{});
        std.debug.print("  /users - Show active users with their tags\n", .{});
        std.debug.print("  /quit or Ctrl-C to exit\n", .{});
        std.debug.print("{s}\n\n", .{"-" ** 50});

        // Start message display thread
        const display_thread = try std.Thread.spawn(.{}, displayLoop, .{self});

        // Handle input in main thread
        try self.inputLoop();

        // Cleanup
        self.running.store(false, .monotonic);
        
        // Join all threads
        for (self.relay_threads.items) |thread| {
            thread.join();
        }
        display_thread.join();
    }

    fn relayReceiveLoop(self: *Self, relay_idx: usize) void {
        const relay = &self.relays.items[relay_idx];
        
        while (self.running.load(.monotonic)) {
            const msg = relay.receiveMessage() catch |err| {
                if (err == error.WouldBlock or err == error.Again) {
                    // No data available, yield to avoid busy-waiting
                    std.time.sleep(1_000_000); // 1ms
                    continue;
                } else if (self.running.load(.monotonic)) {
                    if (self.debug_mode) {
                        std.debug.print("[{s}] Receive error: {}\n", .{ relay.url, err });
                    }
                    std.time.sleep(100_000_000); // 100ms backoff on error
                }
                continue;
            };

            const message = msg orelse {
                std.time.sleep(1_000_000); // 1ms when no message
                continue;
            };

            // Check for deduplication before queuing
            if (message.type == .EVENT and message.id != null) {
                self.seen_mutex.lock();
                defer self.seen_mutex.unlock();
                
                if (self.seen_events.contains(message.id.?)) {
                    if (self.debug_mode) {
                        std.debug.print("[DEDUP] Skipping duplicate from {s}: {s}\n", .{ relay.url, message.id.? });
                    }
                    message.deinit();
                    continue;
                }
                
                // Mark as seen
                const id_copy = self.allocator.dupe(u8, message.id.?) catch {
                    message.deinit();
                    continue;
                };
                self.seen_events.put(id_copy, {}) catch {
                    self.allocator.free(id_copy);
                    message.deinit();
                    continue;
                };
            }
            
            // Queue the message for display
            self.message_queue.push(message, relay.url) catch |err| {
                if (self.debug_mode) {
                    std.debug.print("[{s}] Failed to queue message: {}\n", .{ relay.url, err });
                }
                message.deinit();
            };
        }
    }

    fn displayLoop(self: *Self) void {
        while (self.running.load(.monotonic)) {
            // Get next message with a short timeout
            const queued = self.message_queue.popWithTimeout(10_000_000) orelse continue; // 10ms timeout
            defer {
                queued.message.deinit();
                self.allocator.free(queued.relay_url);
            }
            
            const message = queued.message;
            const relay_url = queued.relay_url;
            
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
                                if (tags[1].len > 0) {
                                    nickname = tags[1];
                                }
                            }
                        }

                        // Store user info if new
                        if (!is_our_echo and message.author != null and nickname != null) {
                            self.users_mutex.lock();
                            defer self.users_mutex.unlock();
                            
                            if (!self.known_users.contains(message.author.?)) {
                                const author_copy = self.allocator.dupe(u8, message.author.?) catch null;
                                const nick_copy = self.allocator.dupe(u8, nickname.?) catch null;
                                if (author_copy != null and nick_copy != null) {
                                    self.known_users.put(author_copy.?, nick_copy.?) catch {};
                                }
                            }
                        }
                        
                        // Get display name and user tag
                        var name_buf: [128]u8 = undefined;
                        const display_prefix = if (is_our_echo) blk: {
                            break :blk "[You]";
                        } else blk: {
                            const base_name = if (nickname) |n| n else "anon";
                            
                            // Add user ID tag (#xxxx) from first 4 chars of pubkey
                            if (message.author) |author| {
                                if (author.len >= 4) {
                                    const tag = author[0..4];
                                    const formatted = std.fmt.bufPrint(&name_buf, "[{s}#{s}]", .{ base_name, tag }) catch "[anon]";
                                    break :blk formatted;
                                }
                            }
                            
                            const formatted = std.fmt.bufPrint(&name_buf, "[{s}]", .{base_name}) catch "[anon]";
                            break :blk formatted;
                        };

                        if (is_our_echo and self.debug_mode) {
                            std.debug.print("\r🔄 [{s}] Echo confirmed\n> ", .{relay_url});
                        }

                        // Clear current line, print message, restore prompt
                        if (self.debug_mode and message.kind != null) {
                            std.debug.print("\r{s: <50}\r[kind:{d}]{s}: {s}\n> ", .{ " ", message.kind.?, display_prefix, content });
                        } else {
                            std.debug.print("\r{s: <50}\r{s}: {s}\n> ", .{ " ", display_prefix, content });
                        }
                    }
                },
                .EOSE => {
                    if (self.debug_mode) {
                        std.debug.print("\r[{s}] Ready for real-time messages\n> ", .{relay_url});
                    }
                },
                .NOTICE => {
                    if (self.debug_mode) {
                        if (message.content) |content| {
                            std.debug.print("\r[{s}] NOTICE: {s}\n> ", .{ relay_url, content });
                        }
                    }
                },
                .OK => {
                    if (self.debug_mode) {
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
                                    std.debug.print("\r{s} [{s}] Accepted our event\n> ", .{ symbol, relay_url });
                                } else {
                                    const reason = message.content orelse "unknown reason";
                                    std.debug.print("\r{s} [{s}] Rejected: {s}\n> ", .{ symbol, relay_url, reason });
                                }
                            }
                        }
                    }
                },
                .AUTH => {
                    // Note: AUTH handling should be done in the relay thread
                    if (self.debug_mode and message.content != null) {
                        std.debug.print("\r[{s}] AUTH challenge: {s}\n> ", .{ relay_url, message.content.? });
                    }
                },
                else => {},
            }
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
        
        if (self.debug_mode) {
            std.debug.print("[{s}] AUTH response sent\n", .{relay.url});
        }
    }

    fn showUserList(self: *Self) void {
        self.users_mutex.lock();
        defer self.users_mutex.unlock();
        
        std.debug.print("\n=== Active Users ===\n", .{});
        
        var iter = self.known_users.iterator();
        var count: usize = 0;
        while (iter.next()) |entry| {
            const pubkey = entry.key_ptr.*;
            const nickname = entry.value_ptr.*;
            if (pubkey.len >= 4) {
                const tag = pubkey[0..4];
                std.debug.print("  {s}#{s} (full: {s}...)\n", .{ nickname, tag, pubkey[0..16] });
                count += 1;
            }
        }
        
        if (count == 0) {
            std.debug.print("  No other users seen yet\n", .{});
        }
        
        std.debug.print("\nUse @username#tag or just #tag to mention users\n", .{});
        std.debug.print("{s}\n> ", .{"-" ** 30});
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
                } else if (std.mem.eql(u8, trimmed, "/users")) {
                    self.showUserList();
                    continue;
                }

                // Send message
                try self.sendMessage(trimmed);
                if (self.debug_mode) {
                    std.debug.print("Sent: {s}\n", .{trimmed});
                }
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
            &[_][]const u8{ "client", "zig-chat" },
        };

        // Create only kind 20000 (ephemeral) event for chat messages
        var event = try nostr_crypto.NostrEvent.create(self.keypair, 20000, &tags, content, self.allocator);

        // Convert event to JSON
        const event_json = try event.toJson(self.allocator);
        defer self.allocator.free(event_json);

        // Create EVENT command
        var command_buffer: [4096]u8 = undefined;
        const command = try std.fmt.bufPrint(&command_buffer, "[\"EVENT\",{s}]", .{event_json});

        if (self.debug_mode) {
            std.debug.print("\n[EPHEMERAL] Sending kind 20000 to {} relays...\n", .{self.relays.items.len});
            std.debug.print("Sending: {s}\n", .{command});
        }

        // Send both events to all relays in parallel
        var sent_count: usize = 0;
        for (self.relays.items) |*relay| {
            // Skip read-only relays
            if (!relay.can_write) {
                if (self.debug_mode) {
                    std.debug.print("[{s}] Skipping (read-only relay)\n", .{relay.url});
                }
                continue;
            }
            
            // Send ephemeral message (kind 20000)
            if (relay.is_tls) {
                relay.tls_client.?.sendText(command) catch |err| {
                    if (self.debug_mode) {
                        std.debug.print("[{s}] ❌ Failed to send: {}\n", .{ relay.url, err });
                    }
                    continue;
                };
            } else {
                relay.ws_client.?.sendText(command) catch |err| {
                    if (self.debug_mode) {
                        std.debug.print("[{s}] ❌ Failed to send: {}\n", .{ relay.url, err });
                    }
                    continue;
                };
            }
            
            if (self.debug_mode) {
                std.debug.print("[{s}] ✓ Sent ephemeral message\n", .{relay.url});
            }
            sent_count += 1;
        }
        
        if (self.debug_mode) {
            std.debug.print("\n📤 Published ephemeral message to {}/{} relays\n", .{ sent_count, self.relays.items.len });
            std.debug.print("Event ID: {s}\n", .{ event.id });
        }
        
        // Store our event ID to track when it comes back
        self.last_sent_ids[0] = event.id;
        @memset(&self.last_sent_ids[1], 0); // Clear second ID since we only send one event now
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .monotonic);
        if (!std.mem.eql(u8, self.username, "anon")) {
            self.allocator.free(self.username);
        }
        
        // Clean up seen events map
        self.seen_mutex.lock();
        var iter = self.seen_events.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.seen_events.deinit();
        self.seen_mutex.unlock();
        
        // Clean up known users map
        self.users_mutex.lock();
        var users_iter = self.known_users.iterator();
        while (users_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.known_users.deinit();
        self.users_mutex.unlock();
        
        // Clean up message queue
        self.message_queue.deinit();
        
        // Clean up relay threads
        self.relay_threads.deinit();
        
        // Clean up all relay clients
        for (self.relays.items) |*relay| {
            relay.deinit();
        }
        self.relays.deinit();
    }
};
