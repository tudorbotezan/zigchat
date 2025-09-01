const std = @import("std");
const NostrWsClient = @import("nostr_ws_client.zig").NostrWsClient;
const nostr_crypto = @import("nostr_crypto.zig");
const MessageQueue = @import("message_queue.zig").MessageQueue;
const builtin = @import("builtin");
const os = std.os;
const AccountStore = @import("account_store.zig").AccountStore;
const Account = @import("account_store.zig").Account;
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
    blocked_users: std.hash_map.StringHashMap(void), // Track blocked user public keys
    blocked_mutex: std.Thread.Mutex,
    blocked_names: std.hash_map.StringHashMap(void), // Track blocked usernames/patterns
    blocked_names_mutex: std.Thread.Mutex,
    input_buffer: std.ArrayList(u8), // Buffer to store current user input
    input_mutex: std.Thread.Mutex, // Mutex to protect input buffer
    // Store original terminal settings for POSIX; on Windows we skip raw mode
    original_termios: ?std.posix.termios = null,
    // Windows console mode backup (only used on Windows builds)
    original_console_mode: ?u32 = null,
    
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: []const u8, primary_relay: []const u8, debug_mode: bool) Self {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        // Load or create account
        var store = AccountStore.init(allocator);
        var username: []const u8 = "anon";
        var keypair: nostr_crypto.KeyPair = undefined;

        var accounts = store.listAccounts() catch std.ArrayList(Account).init(allocator);
        defer {
            // free account names
            for (accounts.items) |acc| allocator.free(acc.name);
            accounts.deinit();
        }

        if (accounts.items.len > 0) {
            stdout.print("Select account or 0 to create new:\n", .{}) catch {};
            // Display list
            var i: usize = 0;
            while (i < accounts.items.len) : (i += 1) {
                stdout.print("  {}: {s}\n", .{ i + 1, accounts.items[i].name }) catch {};
            }
            stdout.print("Choice [1-{} | 0]: ", .{accounts.items.len}) catch {};

            var choice_buf: [16]u8 = undefined;
            var selection: usize = 0;
            if (stdin.readUntilDelimiterOrEof(&choice_buf, '\n') catch null) |raw| {
                const t = std.mem.trim(u8, raw, " \t\r\n");
                if (t.len > 0) {
                    selection = std.fmt.parseInt(usize, t, 10) catch 0;
                }
            }

            if (selection >= 1 and selection <= accounts.items.len) {
                const picked = accounts.items[selection - 1];
                const priv_hex = store.loadPrivateKeyHex(picked.name) catch null;
                if (priv_hex) |hex| {
                    defer allocator.free(hex);
                    username = allocator.dupe(u8, picked.name) catch "anon";
                    keypair = nostr_crypto.KeyPair.fromHex(hex) catch blk: {
                        std.debug.print("Invalid stored key; generating new one.\n", .{});
                        break :blk nostr_crypto.KeyPair.generate() catch blk2: {
                            // Fallback to a known test keypair
                            var test_keypair: nostr_crypto.KeyPair = undefined;
                            @memset(&test_keypair.private_key, 0);
                            test_keypair.private_key[31] = 1;
                            const pubkey_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
                            _ = std.fmt.hexToBytes(&test_keypair.public_key, pubkey_hex) catch unreachable;
                            break :blk2 test_keypair;
                        };
                    };
                } else {
                    std.debug.print("Failed to load account; generating new one.\n", .{});
                    const new = nostr_crypto.KeyPair.generate() catch blk2: {
                        var test_keypair: nostr_crypto.KeyPair = undefined;
                        @memset(&test_keypair.private_key, 0);
                        test_keypair.private_key[31] = 1;
                        const pubkey_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
                        _ = std.fmt.hexToBytes(&test_keypair.public_key, pubkey_hex) catch unreachable;
                        break :blk2 test_keypair;
                    };
                    keypair = new;
                }
            } else {
                // New account flow
                stdout.print("Enter new username: ", .{}) catch {};
                var username_buf: [64]u8 = undefined;
                var entered: []const u8 = "anon";
                if (stdin.readUntilDelimiterOrEof(&username_buf, '\n') catch null) |input| {
                    const trimmed = std.mem.trim(u8, input, " \t\r\n");
                    if (trimmed.len > 0) entered = trimmed;
                }
                const sanitized_alloc = store.sanitizeName(entered) catch entered;
                const sanitized_is_alloc = !std.mem.eql(u8, sanitized_alloc, entered);
                defer if (sanitized_is_alloc) allocator.free(sanitized_alloc);

                username = allocator.dupe(u8, sanitized_alloc) catch "anon";
                keypair = nostr_crypto.KeyPair.generate() catch blk2: {
                    var test_keypair: nostr_crypto.KeyPair = undefined;
                    @memset(&test_keypair.private_key, 0);
                    test_keypair.private_key[31] = 1;
                    const pubkey_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
                    _ = std.fmt.hexToBytes(&test_keypair.public_key, pubkey_hex) catch unreachable;
                    break :blk2 test_keypair;
                };

                // Save account file; avoid clobber by adding suffix if exists
                var final_name = username;
                var name_changed = false;
                var suffix: usize = 2;
                while (store.accountExists(final_name)) : (suffix += 1) {
                    const candidate = std.fmt.allocPrint(allocator, "{s}-{d}", .{ username, suffix }) catch break;
                    if (!store.accountExists(candidate)) {
                        final_name = candidate;
                        name_changed = true;
                        break;
                    }
                    allocator.free(candidate);
                }

                // Convert privkey to hex
                var priv_hex_buf: [64]u8 = undefined;
                const priv_hex_str = std.fmt.bufPrint(&priv_hex_buf, "{}", .{std.fmt.fmtSliceHexLower(&keypair.private_key)}) catch "";
                store.savePrivateKeyHex(final_name, priv_hex_str) catch {
                    if (debug_mode) std.debug.print("Warning: failed to save account.\n", .{});
                };
                // If we modified name, keep username consistent
                if (name_changed) {
                    allocator.free(username);
                    username = allocator.dupe(u8, final_name) catch username;
                    allocator.free(final_name);
                }
            }
        } else {
            // No accounts exist yet: create one
            stdout.print("Enter your username: ", .{}) catch {};
            var username_buf: [64]u8 = undefined;
            var entered: []const u8 = "anon";
            if (stdin.readUntilDelimiterOrEof(&username_buf, '\n') catch null) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\r\n");
                if (trimmed.len > 0) entered = trimmed;
            }
            const sanitized_alloc = store.sanitizeName(entered) catch entered;
            const sanitized_is_alloc = !std.mem.eql(u8, sanitized_alloc, entered);
            defer if (sanitized_is_alloc) allocator.free(sanitized_alloc);
            username = allocator.dupe(u8, sanitized_alloc) catch "anon";

            keypair = nostr_crypto.KeyPair.generate() catch blk2: {
                var test_keypair: nostr_crypto.KeyPair = undefined;
                @memset(&test_keypair.private_key, 0);
                test_keypair.private_key[31] = 1;
                const pubkey_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
                _ = std.fmt.hexToBytes(&test_keypair.public_key, pubkey_hex) catch unreachable;
                break :blk2 test_keypair;
            };
            var priv_hex_buf: [64]u8 = undefined;
            const priv_hex_str = std.fmt.bufPrint(&priv_hex_buf, "{}", .{std.fmt.fmtSliceHexLower(&keypair.private_key)}) catch "";
            store.savePrivateKeyHex(username, priv_hex_str) catch {
                if (debug_mode) std.debug.print("Warning: failed to save account.\n", .{});
            };
        }

        if (debug_mode) {
            std.debug.print("Using account '{s}'\n", .{username});
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
            .blocked_users = std.hash_map.StringHashMap(void).init(allocator),
            .blocked_mutex = .{},
            .blocked_names = std.hash_map.StringHashMap(void).init(allocator),
            .blocked_names_mutex = .{},
            .input_buffer = std.ArrayList(u8).init(allocator),
            .input_mutex = .{},
            .original_termios = null,
        };
        
        // Initialize last_sent_ids
        @memset(&client.last_sent_ids[0], 0);
        @memset(&client.last_sent_ids[1], 0);
        
        // Load blocked users from file
        client.loadBlockedUsers() catch |err| {
            if (debug_mode) {
                std.debug.print("Could not load blocked users: {}\n", .{err});
            }
        };
        
        // Load blocked names from file
        client.loadBlockedNames() catch |err| {
            if (debug_mode) {
                std.debug.print("Could not load blocked names: {}\n", .{err});
            }
        };
        
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
        std.debug.print("  /block <id> or /b <id> - Block a user (by pubkey, #tag, or name#tag)\n", .{});
        std.debug.print("  /unblock <id> - Unblock a user\n", .{});
        std.debug.print("  /blocks - List blocked users\n", .{});
        std.debug.print("  /blockname <pattern> - Block a username or pattern (e.g., ME*)\n", .{});
        std.debug.print("  /unblockname <pattern> - Unblock a username or pattern\n", .{});
        std.debug.print("  /blockednames - List blocked names/patterns\n", .{});
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
        message_loop: while (self.running.load(.monotonic)) {
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
                        // Check if user is blocked by pubkey
                        if (message.author) |author| {
                            self.blocked_mutex.lock();
                            const is_blocked = self.blocked_users.contains(author);
                            self.blocked_mutex.unlock();
                            
                            if (is_blocked) {
                                continue; // Skip messages from blocked users
                            }
                        }
                        
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
                        
                        // Check if username is blocked
                        if (nickname) |nick| {
                            self.blocked_names_mutex.lock();
                            defer self.blocked_names_mutex.unlock();
                            
                            // Check exact match
                            if (self.blocked_names.contains(nick)) {
                                continue; // Skip messages from blocked names
                            }
                            
                            // Check pattern matching (e.g., "ME#*" pattern)
                            var iter = self.blocked_names.iterator();
                            while (iter.next()) |entry| {
                                const pattern = entry.key_ptr.*;
                                if (self.matchesPattern(nick, pattern)) {
                                    continue :message_loop; // Skip messages matching blocked patterns
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
                            // Use actual username with tag for consistency
                            const pubkey_hex = std.fmt.fmtSliceHexLower(&self.keypair.public_key);
                            var hex_buf: [64]u8 = undefined;
                            const hex_str = std.fmt.bufPrint(&hex_buf, "{}", .{pubkey_hex}) catch "";
                            if (hex_str.len >= 4) {
                                const tag = hex_str[0..4];
                                const formatted = std.fmt.bufPrint(&name_buf, "[{s}#{s}]", .{ self.username, tag }) catch "[anon]";
                                break :blk formatted;
                            }
                            const formatted = std.fmt.bufPrint(&name_buf, "[{s}]", .{self.username}) catch "[anon]";
                            break :blk formatted;
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

                        // Use ANSI escape codes for proper display management
                        const orange = "\x1b[38;5;208m";
                        const reset = "\x1b[0m";
                        
                        // Get current input buffer content
                        self.input_mutex.lock();
                        const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                        self.input_mutex.unlock();
                        defer if (input_copy.len > 0) self.allocator.free(input_copy);
                        
                        // Move to beginning of line, clear it, print message, then new prompt with input
                        const stdout = std.io.getStdOut().writer();
                        
                        if (self.debug_mode and message.kind != null) {
                            if (is_our_echo) {
                                stdout.print("\r\x1b[2K[kind:{d}]{s}{s}{s}: {s}\n> {s}", .{ message.kind.?, orange, display_prefix, reset, content, input_copy }) catch {};
                            } else {
                                stdout.print("\r\x1b[2K[kind:{d}]{s}: {s}\n> {s}", .{ message.kind.?, display_prefix, content, input_copy }) catch {};
                            }
                        } else {
                            if (is_our_echo) {
                                stdout.print("\r\x1b[2K{s}{s}{s}: {s}\n> {s}", .{ orange, display_prefix, reset, content, input_copy }) catch {};
                            } else {
                                stdout.print("\r\x1b[2K{s}: {s}\n> {s}", .{ display_prefix, content, input_copy }) catch {};
                            }
                        }
                        // Flush output to ensure it's displayed immediately
                        std.io.getStdOut().sync() catch {};
                    }
                },
                .EOSE => {
                    if (self.debug_mode) {
                        const stdout = std.io.getStdOut().writer();
                        self.input_mutex.lock();
                        const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                        self.input_mutex.unlock();
                        defer if (input_copy.len > 0) self.allocator.free(input_copy);
                        stdout.print("\r\x1b[2K[{s}] Ready for real-time messages\n> {s}", .{ relay_url, input_copy }) catch {};
                    }
                },
                .NOTICE => {
                    if (self.debug_mode) {
                        if (message.content) |content| {
                            const stdout = std.io.getStdOut().writer();
                            self.input_mutex.lock();
                            const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                            self.input_mutex.unlock();
                            defer if (input_copy.len > 0) self.allocator.free(input_copy);
                            stdout.print("\r\x1b[2K[{s}] NOTICE: {s}\n> {s}", .{ relay_url, content, input_copy }) catch {};
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
                                const stdout = std.io.getStdOut().writer();
                                self.input_mutex.lock();
                                const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                                self.input_mutex.unlock();
                                defer if (input_copy.len > 0) self.allocator.free(input_copy);
                                
                                if (message.ok_status orelse false) {
                                    stdout.print("\r\x1b[2K{s} [{s}] Accepted our event\n> {s}", .{ symbol, relay_url, input_copy }) catch {};
                                } else {
                                    const reason = message.content orelse "unknown reason";
                                    stdout.print("\r\x1b[2K{s} [{s}] Rejected: {s}\n> {s}", .{ symbol, relay_url, reason, input_copy }) catch {};
                                }
                            }
                        }
                    }
                },
                .AUTH => {
                    // Note: AUTH handling should be done in the relay thread
                    if (self.debug_mode and message.content != null) {
                        const stdout = std.io.getStdOut().writer();
                        self.input_mutex.lock();
                        const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                        self.input_mutex.unlock();
                        defer if (input_copy.len > 0) self.allocator.free(input_copy);
                        stdout.print("\r\x1b[2K[{s}] AUTH challenge: {s}\n> {s}", .{ relay_url, message.content.?, input_copy }) catch {};
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

    fn enableRawMode(self: *Self) !void {
        if (builtin.os.tag == .windows) {
            // Windows: skip configuring raw mode to avoid console API differences.
            // Keep behavior line-buffered; interactive features degrade gracefully.
            self.original_console_mode = null;
            return;
        } else {
            const stdin = std.io.getStdIn();
            
            // Get current terminal settings
            var termios = try std.posix.tcgetattr(stdin.handle);
            
            // Save original settings
            self.original_termios = termios;
            
            // Modify flags for raw mode
            // Disable canonical mode (line buffering) and echo
            termios.lflag.ICANON = false;
            termios.lflag.ECHO = false;
            termios.lflag.ECHONL = false;
            termios.lflag.ISIG = false; // Disable Ctrl-C, Ctrl-Z signals
            termios.lflag.IEXTEN = false;
            
            // Disable input processing
            termios.iflag.IXON = false; // Disable Ctrl-S, Ctrl-Q
            termios.iflag.ICRNL = false; // Don't translate CR to NL
            termios.iflag.BRKINT = false;
            termios.iflag.INPCK = false;
            termios.iflag.ISTRIP = false;
            
            // Set minimum characters and timeout
            termios.cc[@intFromEnum(std.posix.V.TIME)] = 0; // No timeout
            termios.cc[@intFromEnum(std.posix.V.MIN)] = 1; // Read 1 character at a time
            
            // Apply the new settings
            try std.posix.tcsetattr(stdin.handle, .FLUSH, termios);
        }
    }
    
    fn disableRawMode(self: *Self) void {
        if (builtin.os.tag == .windows) {
            // Nothing to restore for Windows in current implementation
            return;
        } else {
            if (self.original_termios) |termios| {
                const stdin = std.io.getStdIn();
                std.posix.tcsetattr(stdin.handle, .FLUSH, termios) catch {};
            }
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
        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut().writer();
        
        // Enable raw mode
        try self.enableRawMode();
        defer self.disableRawMode();
        
        // Initial prompt
        try stdout.print("> ", .{});
        
        while (self.running.load(.monotonic)) {
            var char_buf: [1]u8 = undefined;
            const bytes_read = stdin.read(&char_buf) catch |err| {
                if (err == error.WouldBlock) {
                    std.time.sleep(10_000_000); // 10ms
                    continue;
                }
                return err;
            };
            
            if (bytes_read == 0) {
                std.time.sleep(10_000_000); // 10ms
                continue;
            }
            
            const char = char_buf[0];
            
            // Handle special characters
            if (char == '\r' or char == '\n') { // Enter key (CR or LF)
                // Process the command
                self.input_mutex.lock();
                const input_copy = self.allocator.dupe(u8, self.input_buffer.items) catch "";
                self.input_buffer.clearRetainingCapacity();
                self.input_mutex.unlock();
                defer if (input_copy.len > 0) self.allocator.free(input_copy);
                
                const trimmed = std.mem.trim(u8, input_copy, " \t\r\n");
                
                if (trimmed.len == 0) {
                    try stdout.print("\n> ", .{});
                    continue;
                }
                
                if (std.mem.eql(u8, trimmed, "/quit")) {
                    try stdout.print("\nGoodbye!\n", .{});
                    break;
                } else if (std.mem.eql(u8, trimmed, "/users")) {
                    try stdout.print("\n", .{});
                    self.showUserList();
                    continue;
                } else if (std.mem.eql(u8, trimmed, "/blocks")) {
                    try stdout.print("\n", .{});
                    self.showBlockedList();
                    continue;
                } else if (std.mem.startsWith(u8, trimmed, "/block ") or std.mem.startsWith(u8, trimmed, "/b ")) {
                    const space_idx = std.mem.indexOf(u8, trimmed, " ") orelse {
                        try stdout.print("\n> ", .{});
                        continue;
                    };
                    const user_id = std.mem.trim(u8, trimmed[space_idx + 1 ..], " \t");
                    if (user_id.len > 0) {
                        try stdout.print("\n", .{});
                        try self.blockUser(user_id);
                    } else {
                        try stdout.print("\nUsage: /block <user_id> or /b <user_id>\n> ", .{});
                    }
                    continue;
                } else if (std.mem.startsWith(u8, trimmed, "/unblock ")) {
                    const space_idx = std.mem.indexOf(u8, trimmed, " ") orelse {
                        try stdout.print("\n> ", .{});
                        continue;
                    };
                    const user_id = std.mem.trim(u8, trimmed[space_idx + 1 ..], " \t");
                    if (user_id.len > 0) {
                        try stdout.print("\n", .{});
                        try self.unblockUser(user_id);
                    } else {
                        try stdout.print("\nUsage: /unblock <user_id>\n> ", .{});
                    }
                    continue;
                } else if (std.mem.startsWith(u8, trimmed, "/blockname ")) {
                    const space_idx = std.mem.indexOf(u8, trimmed, " ") orelse {
                        try stdout.print("\n> ", .{});
                        continue;
                    };
                    const name_pattern = std.mem.trim(u8, trimmed[space_idx + 1 ..], " \t");
                    if (name_pattern.len > 0) {
                        try stdout.print("\n", .{});
                        try self.blockName(name_pattern);
                    } else {
                        try stdout.print("\nUsage: /blockname <name_or_pattern>\n", .{});
                        try stdout.print("Examples:\n", .{});
                        try stdout.print("  /blockname ME      - blocks exact name 'ME'\n", .{});
                        try stdout.print("  /blockname ME*     - blocks names starting with 'ME'\n", .{});
                        try stdout.print("  /blockname *spam*  - blocks names containing 'spam'\n> ", .{});
                    }
                    continue;
                } else if (std.mem.startsWith(u8, trimmed, "/unblockname ")) {
                    const space_idx = std.mem.indexOf(u8, trimmed, " ") orelse {
                        try stdout.print("\n> ", .{});
                        continue;
                    };
                    const name_pattern = std.mem.trim(u8, trimmed[space_idx + 1 ..], " \t");
                    if (name_pattern.len > 0) {
                        try stdout.print("\n", .{});
                        try self.unblockName(name_pattern);
                    } else {
                        try stdout.print("\nUsage: /unblockname <name_or_pattern>\n> ", .{});
                    }
                    continue;
                } else if (std.mem.eql(u8, trimmed, "/blockednames")) {
                    try stdout.print("\n", .{});
                    self.showBlockedNames();
                    continue;
                }
                
                // Clear the line and send message
                try stdout.print("\r\x1b[2K", .{}); // Clear entire line
                try self.sendMessage(trimmed);
                
            } else if (char == 127 or char == 8) { // Backspace (DEL or BS)
                self.input_mutex.lock();
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                    // Clear line and redraw with updated buffer
                    try stdout.print("\r\x1b[2K> {s}", .{self.input_buffer.items});
                    std.io.getStdOut().sync() catch {};
                }
                self.input_mutex.unlock();
            } else if (char == 3) { // Ctrl-C
                try stdout.print("\n", .{});
                break;
            } else if (char == 4) { // Ctrl-D (EOF)
                if (self.input_buffer.items.len == 0) {
                    try stdout.print("\n", .{});
                    break;
                }
            } else if (char >= 32 and char < 127) { // Printable characters
                self.input_mutex.lock();
                self.input_buffer.append(char) catch {};
                self.input_mutex.unlock();
                // Echo the character and flush immediately
                try stdout.writeByte(char);
                std.io.getStdOut().sync() catch {};
            } else if (char == 27) { // ESC sequence (arrow keys, etc.)
                // Read next two bytes for arrow keys
                var seq: [2]u8 = undefined;
                if (stdin.read(&seq) catch 0 == 2) {
                    if (seq[0] == '[') {
                        // Handle arrow keys if needed
                        // For now, just ignore them
                    }
                }
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

    fn blockUser(self: *Self, user_id: []const u8) !void {
        // Try to resolve the user ID to a public key
        const pubkey = self.resolveUserToPubkey(user_id) catch null;
        
        if (pubkey == null) {
            std.debug.print("User not found: {s}\n", .{user_id});
            std.debug.print("You can use: full pubkey, #tag (e.g., #79be), or username#tag\n", .{});
            return;
        }
        
        self.blocked_mutex.lock();
        
        // Check if already blocked
        if (self.blocked_users.contains(pubkey.?)) {
            self.blocked_mutex.unlock();
            std.debug.print("User already blocked: {s}\n", .{user_id});
            return;
        }
        
        // Add to blocked list
        const pubkey_copy = try self.allocator.dupe(u8, pubkey.?);
        try self.blocked_users.put(pubkey_copy, {});
        
        self.blocked_mutex.unlock();
        
        // Save to file (without holding the lock)
        self.saveBlockedUsers() catch |err| {
            if (self.debug_mode) {
                std.debug.print("Failed to save blocked users: {}\n", .{err});
            }
        };
        
        std.debug.print("Blocked user: {s}\n", .{user_id});
        if (pubkey.?.len > 16) {
            std.debug.print("  Pubkey: {s}...\n", .{pubkey.?[0..16]});
        }
    }
    
    fn unblockUser(self: *Self, user_id: []const u8) !void {
        // Try to resolve the user ID to a public key
        const pubkey = self.resolveUserToPubkey(user_id) catch null;
        
        if (pubkey == null) {
            // If not found in known users, try as raw pubkey
            if (user_id.len == 64) {
                self.blocked_mutex.lock();
                
                if (self.blocked_users.fetchRemove(user_id)) |entry| {
                    self.allocator.free(entry.key);
                    self.blocked_mutex.unlock();
                    
                    // Save to file (without holding the lock)
                    self.saveBlockedUsers() catch |err| {
                        if (self.debug_mode) {
                            std.debug.print("Failed to save blocked users: {}\n", .{err});
                        }
                    };
                    
                    std.debug.print("Unblocked user: {s}\n", .{user_id});
                    return;
                } else {
                    self.blocked_mutex.unlock();
                }
            }
            
            std.debug.print("User not found in block list: {s}\n", .{user_id});
            return;
        }
        
        self.blocked_mutex.lock();
        
        if (self.blocked_users.fetchRemove(pubkey.?)) |entry| {
            self.allocator.free(entry.key);
            self.blocked_mutex.unlock();
            
            // Save to file (without holding the lock)
            self.saveBlockedUsers() catch |err| {
                if (self.debug_mode) {
                    std.debug.print("Failed to save blocked users: {}\n", .{err});
                }
            };
            
            std.debug.print("Unblocked user: {s}\n", .{user_id});
        } else {
            self.blocked_mutex.unlock();
            std.debug.print("User not in block list: {s}\n", .{user_id});
        }
    }
    
    fn showBlockedList(self: *Self) void {
        self.blocked_mutex.lock();
        defer self.blocked_mutex.unlock();
        
        std.debug.print("\n=== Blocked Users ===\n", .{});
        
        if (self.blocked_users.count() == 0) {
            std.debug.print("  No blocked users\n", .{});
            std.debug.print("{s}\n> ", .{"-" ** 30});
            return;
        }
        
        var iter = self.blocked_users.iterator();
        var count: usize = 0;
        while (iter.next()) |entry| {
            const pubkey = entry.key_ptr.*;
            
            // Try to find nickname for this pubkey
            self.users_mutex.lock();
            const nickname = self.known_users.get(pubkey);
            self.users_mutex.unlock();
            
            if (nickname) |nick| {
                if (pubkey.len >= 4) {
                    std.debug.print("  {s}#{s} ({s}...)\n", .{ nick, pubkey[0..4], pubkey[0..16] });
                }
            } else {
                if (pubkey.len >= 16) {
                    std.debug.print("  #{s} ({s}...)\n", .{ pubkey[0..4], pubkey[0..16] });
                }
            }
            count += 1;
        }
        
        std.debug.print("\nTotal: {} blocked users\n", .{count});
        std.debug.print("{s}\n> ", .{"-" ** 30});
    }
    
    fn resolveUserToPubkey(self: *Self, user_id: []const u8) !?[]const u8 {
        // Check if it's a full pubkey (64 hex chars)
        if (user_id.len == 64) {
            // Verify it's valid hex
            for (user_id) |c| {
                if (!std.ascii.isHex(c)) {
                    return null;
                }
            }
            return user_id;
        }
        
        // Check if it's a #tag format (e.g., #79be)
        if (user_id[0] == '#' and user_id.len >= 2) {
            const tag = user_id[1..];
            
            self.users_mutex.lock();
            defer self.users_mutex.unlock();
            
            // Search for matching pubkey by tag prefix
            var iter = self.known_users.iterator();
            while (iter.next()) |entry| {
                const pubkey = entry.key_ptr.*;
                if (std.mem.startsWith(u8, pubkey, tag)) {
                    return pubkey;
                }
            }
        }
        
        // Check if it's username#tag format
        if (std.mem.indexOf(u8, user_id, "#")) |hash_idx| {
            const username = user_id[0..hash_idx];
            const tag = user_id[hash_idx + 1 ..];
            
            self.users_mutex.lock();
            defer self.users_mutex.unlock();
            
            // Search for matching user
            var iter = self.known_users.iterator();
            while (iter.next()) |entry| {
                const pubkey = entry.key_ptr.*;
                const nick = entry.value_ptr.*;
                
                if (std.mem.eql(u8, nick, username) and std.mem.startsWith(u8, pubkey, tag)) {
                    return pubkey;
                }
            }
        }
        
        return null;
    }
    
    fn loadBlockedUsers(self: *Self) !void {
        var store = AccountStore.init(self.allocator);
        const base = store.getConfigRoot() catch return; // skip if no env
        defer self.allocator.free(base);

        const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ base, "blocked_users.txt" });
        defer self.allocator.free(file_path);

        const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.tokenizeAny(u8, content, "\n\r");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 64) {
                const pubkey_copy = try self.allocator.dupe(u8, trimmed);
                try self.blocked_users.put(pubkey_copy, {});
            }
        }

        if (self.debug_mode and self.blocked_users.count() > 0) {
            std.debug.print("Loaded {} blocked users\n", .{self.blocked_users.count()});
        }
    }
    
    fn saveBlockedUsers(self: *Self) !void {
        var store = AccountStore.init(self.allocator);
        const base = store.getConfigRoot() catch return; // skip if no env
        defer self.allocator.free(base);

        std.fs.makeDirAbsolute(base) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ base, "blocked_users.txt" });
        defer self.allocator.free(file_path);

        const file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();

        self.blocked_mutex.lock();
        defer self.blocked_mutex.unlock();

        var iter = self.blocked_users.iterator();
        while (iter.next()) |entry| {
            const pubkey = entry.key_ptr.*;
            try file.writer().print("{s}\n", .{pubkey});
        }
    }
    
    fn blockName(self: *Self, name_pattern: []const u8) !void {
        self.blocked_names_mutex.lock();
        
        // Check if already blocked
        if (self.blocked_names.contains(name_pattern)) {
            self.blocked_names_mutex.unlock();
            std.debug.print("Name/pattern already blocked: {s}\n", .{name_pattern});
            return;
        }
        
        // Add to blocked names list
        const name_copy = try self.allocator.dupe(u8, name_pattern);
        try self.blocked_names.put(name_copy, {});
        
        self.blocked_names_mutex.unlock();
        
        // Save to file (after releasing the lock)
        self.saveBlockedNames() catch |err| {
            if (self.debug_mode) {
                std.debug.print("Failed to save blocked names: {}\n", .{err});
            }
        };
        
        std.debug.print("Blocked name/pattern: {s}\n", .{name_pattern});
    }
    
    fn unblockName(self: *Self, name_pattern: []const u8) !void {
        self.blocked_names_mutex.lock();
        
        const removed = self.blocked_names.fetchRemove(name_pattern);
        if (removed) |entry| {
            self.allocator.free(entry.key);
        }
        
        self.blocked_names_mutex.unlock();
        
        if (removed != null) {
            // Save to file (after releasing the lock)
            self.saveBlockedNames() catch |err| {
                if (self.debug_mode) {
                    std.debug.print("Failed to save blocked names: {}\n", .{err});
                }
            };
            
            std.debug.print("Unblocked name/pattern: {s}\n", .{name_pattern});
        } else {
            std.debug.print("Name/pattern not in block list: {s}\n", .{name_pattern});
        }
    }
    
    fn showBlockedNames(self: *Self) void {
        self.blocked_names_mutex.lock();
        defer self.blocked_names_mutex.unlock();
        
        std.debug.print("\n=== Blocked Names/Patterns ===\n", .{});
        
        if (self.blocked_names.count() == 0) {
            std.debug.print("  No blocked names\n", .{});
            std.debug.print("{s}\n> ", .{"-" ** 30});
            return;
        }
        
        var iter = self.blocked_names.iterator();
        var count: usize = 0;
        while (iter.next()) |entry| {
            const name_pattern = entry.key_ptr.*;
            std.debug.print("  {s}\n", .{name_pattern});
            count += 1;
        }
        
        std.debug.print("\nTotal: {} blocked names/patterns\n", .{count});
        std.debug.print("{s}\n> ", .{"-" ** 30});
    }
    
    fn matchesPattern(self: *Self, text: []const u8, pattern: []const u8) bool {
        _ = self;
        // Simple wildcard matching: * matches any sequence of characters
        if (pattern.len == 0) return text.len == 0;
        
        var text_idx: usize = 0;
        var pattern_idx: usize = 0;
        var star_idx: ?usize = null;
        var match_idx: usize = 0;
        
        while (text_idx < text.len) {
            if (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
                star_idx = pattern_idx;
                match_idx = text_idx;
                pattern_idx += 1;
            } else if (pattern_idx < pattern.len and 
                      (pattern[pattern_idx] == text[text_idx] or pattern[pattern_idx] == '?')) {
                text_idx += 1;
                pattern_idx += 1;
            } else if (star_idx != null) {
                pattern_idx = star_idx.? + 1;
                match_idx += 1;
                text_idx = match_idx;
            } else {
                return false;
            }
        }
        
        // Check remaining pattern characters are all '*'
        while (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
            pattern_idx += 1;
        }
        
        return pattern_idx == pattern.len;
    }
    
    fn loadBlockedNames(self: *Self) !void {
        // Get home directory
        const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch return;
        defer self.allocator.free(home);
        
        // Build path to blocked names file
        var path_buf: [1024]u8 = undefined;
        const config_dir = try std.fmt.bufPrint(&path_buf, "{s}/.zigchat", .{home});
        
        // Create directory if it doesn't exist
        std.fs.makeDirAbsolute(config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        
        var file_path_buf: [1024]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/blocked_names.txt", .{config_dir});
        
        // Try to open the file
        const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // No blocked names yet
            else => return err,
        };
        defer file.close();
        
        // Read the file
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        
        // Parse each line as a name/pattern
        var lines = std.mem.tokenizeAny(u8, content, "\n\r");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                const name_copy = try self.allocator.dupe(u8, trimmed);
                try self.blocked_names.put(name_copy, {});
            }
        }
        
        if (self.debug_mode and self.blocked_names.count() > 0) {
            std.debug.print("Loaded {} blocked names/patterns\n", .{self.blocked_names.count()});
        }
    }
    
    fn saveBlockedNames(self: *Self) !void {
        // Get home directory
        const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch return error.NoHomeDir;
        defer self.allocator.free(home);
        
        // Build path to blocked names file
        var path_buf: [1024]u8 = undefined;
        const config_dir = try std.fmt.bufPrint(&path_buf, "{s}/.zigchat", .{home});
        
        // Create directory if it doesn't exist
        std.fs.makeDirAbsolute(config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        
        var file_path_buf: [1024]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/blocked_names.txt", .{config_dir});
        
        // Create/overwrite the file
        const file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();
        
        // Write each blocked name/pattern on a new line
        self.blocked_names_mutex.lock();
        defer self.blocked_names_mutex.unlock();
        
        var iter = self.blocked_names.iterator();
        while (iter.next()) |entry| {
            const name_pattern = entry.key_ptr.*;
            try file.writer().print("{s}\n", .{name_pattern});
        }
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .monotonic);
        
        // Restore terminal to original mode
        self.disableRawMode();
        
        if (!std.mem.eql(u8, self.username, "anon")) {
            self.allocator.free(self.username);
        }
        
        // Clean up input buffer
        self.input_buffer.deinit();
        
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
        
        // Clean up blocked users map
        self.blocked_mutex.lock();
        var blocked_iter = self.blocked_users.iterator();
        while (blocked_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.blocked_users.deinit();
        self.blocked_mutex.unlock();
        
        // Clean up blocked names map
        self.blocked_names_mutex.lock();
        var blocked_names_iter = self.blocked_names.iterator();
        while (blocked_names_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.blocked_names.deinit();
        self.blocked_names_mutex.unlock();
        
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
