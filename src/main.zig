const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "keygen")) {
        try cmdKeygen(allocator);
    } else if (std.mem.eql(u8, command, "whoami")) {
        try cmdWhoami(allocator);
    } else if (std.mem.eql(u8, command, "relay")) {
        if (args.len < 3) {
            try printRelayUsage();
            return;
        }
        const subcommand = args[2];
        if (std.mem.eql(u8, subcommand, "add")) {
            if (args.len < 4) {
                std.debug.print("Error: relay add requires URL\n", .{});
                return;
            }
            try cmdRelayAdd(allocator, args[3]);
        } else if (std.mem.eql(u8, subcommand, "ls")) {
            try cmdRelayList(allocator);
        } else if (std.mem.eql(u8, subcommand, "rm")) {
            if (args.len < 4) {
                std.debug.print("Error: relay rm requires index\n", .{});
                return;
            }
            const index = try std.fmt.parseInt(usize, args[3], 10);
            try cmdRelayRemove(allocator, index);
        } else {
            try printRelayUsage();
        }
    } else if (std.mem.eql(u8, command, "pub")) {
        if (args.len < 3) {
            std.debug.print("Error: pub requires a message\n", .{});
            return;
        }
        try cmdPublish(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "sub")) {
        try cmdSubscribe(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "auth")) {
        if (args.len >= 3 and std.mem.eql(u8, args[2], "test")) {
            try cmdAuthTest(allocator);
        } else {
            std.debug.print("Usage: zigchat auth test\n", .{});
        }
    } else if (std.mem.eql(u8, command, "channel")) {
        const channel = if (args.len > 2) args[2] else "9q";
        const relay = if (args.len > 3) args[3] else "wss://relay.damus.io";
        try cmdChannel(allocator, channel, relay);
    } else if (std.mem.eql(u8, command, "chat")) {
        const channel = if (args.len > 2) args[2] else "9q";
        const relay = if (args.len > 3) args[3] else "wss://relay.damus.io";
        // Check for --debug flag
        var debug_mode = false;
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--debug")) {
                debug_mode = true;
                break;
            }
        }
        try cmdInteractive(allocator, channel, relay, debug_mode);
    } else if (std.mem.eql(u8, command, "ws-test")) {
        const url = if (args.len > 2) args[2] else "ws://localhost:8080";
        try cmdWsTest(allocator, url);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Zigchat - Minimal Nostr TUI Client
        \\
        \\Usage:
        \\  zigchat keygen                  Generate new keypair
        \\  zigchat whoami                  Show current identity
        \\  zigchat relay add <url>         Add relay
        \\  zigchat relay ls                List relays
        \\  zigchat relay rm <index>        Remove relay
        \\  zigchat pub <message>           Publish note
        \\  zigchat sub [options]           Subscribe to notes
        \\  zigchat auth test               Test AUTH flow
        \\  zigchat channel [name] [relay]  Join a channel (default: #9q)
        \\  zigchat chat [name] [relay]     Interactive chat mode (can send messages)
        \\  zigchat ws-test [url]           Test WebSocket connection
        \\
    , .{});
}

fn printRelayUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage:
        \\  zigchat relay add <url>    Add a relay
        \\  zigchat relay ls           List all relays
        \\  zigchat relay rm <index>   Remove relay by index
        \\
    , .{});
}

fn cmdKeygen(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Generating keypair...\n", .{});
    std.debug.print("TODO: Implement key generation\n", .{});
}

fn cmdWhoami(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Current identity:\n", .{});
    std.debug.print("TODO: Load and display identity from config\n", .{});
}

fn cmdRelayAdd(allocator: std.mem.Allocator, url: []const u8) !void {
    _ = allocator;
    std.debug.print("Adding relay: {s}\n", .{url});
    std.debug.print("TODO: Add relay to config\n", .{});
}

fn cmdRelayList(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Configured relays:\n", .{});
    std.debug.print("TODO: List relays from config\n", .{});
}

fn cmdRelayRemove(allocator: std.mem.Allocator, index: usize) !void {
    _ = allocator;
    std.debug.print("Removing relay at index: {}\n", .{index});
    std.debug.print("TODO: Remove relay from config\n", .{});
}

fn cmdPublish(allocator: std.mem.Allocator, message: []const u8) !void {
    _ = allocator;
    std.debug.print("Publishing: {s}\n", .{message});
    std.debug.print("TODO: Sign and publish event\n", .{});
}

fn cmdSubscribe(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("Subscribing to notes...\n", .{});
    std.debug.print("TODO: Connect and subscribe\n", .{});
}

fn cmdAuthTest(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Testing AUTH flow...\n", .{});
    std.debug.print("TODO: Test NIP-42 auth\n", .{});
}

fn cmdChannel(allocator: std.mem.Allocator, channel: []const u8, relay_url: []const u8) !void {
    // Try real WebSocket (both ws:// and wss://)
    if (std.mem.startsWith(u8, relay_url, "ws://") or std.mem.startsWith(u8, relay_url, "wss://")) {
        cmdChannelReal(allocator, channel, relay_url) catch |err| {
            std.debug.print("WebSocket connection failed: {}\n", .{err});

            if (std.mem.startsWith(u8, relay_url, "wss://")) {
                std.debug.print("\nConnection to {s} failed.\n", .{relay_url});
                std.debug.print("Please check your network connection and try again.\n\n", .{});
            }

            std.debug.print("Unable to connect. Please try again later.\n\n", .{});
        };
    } else {
        std.debug.print("Invalid relay URL. Please use ws:// or wss:// protocol.\n", .{});
    }
}

fn cmdChannelReal(allocator: std.mem.Allocator, channel: []const u8, relay_url: []const u8) !void {
    const NostrWsClient = @import("nostr_ws_client.zig").NostrWsClient;

    std.debug.print("\n=== Zigchat TUI - Geohash: {s} ===\n", .{channel});
    std.debug.print("{s}\n", .{"=" ** 50});
    std.debug.print("Relay: {s}\n", .{relay_url});
    std.debug.print("{s}\n\n", .{"=" ** 50});

    var client = NostrWsClient.init(allocator, relay_url, true); // Always debug mode for channel command
    defer client.deinit();

    try client.connect();

    // If channel is "global", subscribe to all messages, otherwise filter by channel
    if (std.mem.eql(u8, channel, "global")) {
        try client.subscribeToGlobal();
    } else {
        try client.subscribeToChannel(channel);
    }

    std.debug.print("Listening for REAL-TIME messages only... (Ctrl-C to quit)\n", .{});
    std.debug.print("{s}\n\n", .{"-" ** 50});

    // Message receive loop
    var message_count: usize = 0;
    while (true) {
        const msg = client.receiveMessage() catch |err| {
            std.debug.print("Error receiving message: {}\n", .{err});
            continue;
        };

        const message = msg orelse {
            // No message received, but still connected
            std.time.sleep(100 * std.time.ns_per_ms);
            continue;
        };

        defer message.deinit();
        message_count += 1;

        switch (message.type) {
            .EVENT => {
                if (message.content) |content| {
                    // Format: [timestamp] author: content
                    const timestamp = message.created_at orelse std.time.timestamp();
                    const author_short = if (message.author) |author|
                        if (author.len > 8) author[0..8] else author
                    else
                        "unknown";

                    std.debug.print("[{d}] {s}: {s}\n", .{ timestamp, author_short, content });
                }
            },
            .EOSE => {
                std.debug.print("--- Ready for real-time messages ---\n", .{});
            },
            .NOTICE => {
                if (message.content) |content| {
                    std.debug.print("NOTICE: {s}\n", .{content});
                }
            },
            .OK => {
                std.debug.print("OK received\n", .{});
            },
            else => {},
        }
    }
}


fn cmdInteractive(allocator: std.mem.Allocator, channel: []const u8, relay_url: []const u8, debug_mode: bool) !void {
    const InteractiveClient = @import("interactive_client.zig").InteractiveClient;

    var client = InteractiveClient.init(allocator, channel, relay_url, debug_mode);
    defer client.deinit();

    try client.start();
}

fn cmdWsTest(allocator: std.mem.Allocator, url: []const u8) !void {
    const WebSocketClient = @import("websocket_client.zig").WebSocketClient;

    std.debug.print("Testing WebSocket connection to: {s}\n", .{url});

    var client = WebSocketClient.init(allocator, url);
    defer client.deinit();

    try client.connect();

    // Send a test message
    try client.sendText("Hello WebSocket!");

    // Receive messages
    std.debug.print("Waiting for messages...\n", .{});
    var count: usize = 0;
    while (count < 5) : (count += 1) {
        if (try client.receive()) |msg| {
            defer allocator.free(msg);
            std.debug.print("Received: {s}\n", .{msg});
        } else {
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }

    std.debug.print("Test complete!\n", .{});
}
