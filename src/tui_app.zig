const std = @import("std");
const NostrClient = @import("nostr_client.zig").NostrClient;

const MAX_MESSAGES = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const channel = if (args.len > 1) args[1] else "9q";
    const relay_url = if (args.len > 2) args[2] else "wss://relay.damus.io";

    std.debug.print("Connecting to {s} to join #{s} channel...\n\n", .{ relay_url, channel });

    // Initialize client
    var client = NostrClient.init(allocator, relay_url);
    defer client.deinit();

    // Connect to relay
    try client.connect();

    // Subscribe to channel
    try client.subscribeToChannel(channel);

    // Message buffer
    var messages = std.ArrayList([]u8).init(allocator);
    defer {
        for (messages.items) |msg| {
            allocator.free(msg);
        }
        messages.deinit();
    }

    std.debug.print("=== Bitchat TUI - Channel #{s} ===\n", .{channel});
    std.debug.print("{s}\n", .{"=" ** 50});
    std.debug.print("Listening for messages... (Ctrl-C to quit)\n\n", .{});

    // Main message loop
    while (true) {
        // Try to receive a message with 100ms timeout
        const msg_opt = try client.receiveMessageTimeout(100);

        if (msg_opt) |msg| {
            // Parse the message and extract content
            if (parseNostrMessage(msg)) |content| {
                // Add to buffer
                try messages.append(try allocator.dupe(u8, content));

                // Display the message
                std.debug.print("{s}\n", .{content});

                // Remove old messages if buffer is full
                if (messages.items.len > MAX_MESSAGES) {
                    const old_msg = messages.orderedRemove(0);
                    allocator.free(old_msg);
                }
            }
            allocator.free(msg);
        }

        // Check for user input (non-blocking would be better)
        // For now, just continue looping
    }
}

fn parseNostrMessage(json_str: []const u8) ?[]const u8 {
    // Basic parsing - look for EVENT messages
    // Format: ["EVENT", "subscription_id", {...event data...}]

    if (!std.mem.startsWith(u8, json_str, "[\"EVENT\"")) {
        return null;
    }

    // Find content field in the JSON
    // This is a very basic parser - in production you'd use proper JSON parsing
    const content_marker = "\"content\":\"";
    const content_start = std.mem.indexOf(u8, json_str, content_marker) orelse return null;
    const content_begin = content_start + content_marker.len;

    // Find the end of content
    var i = content_begin;
    while (i < json_str.len) : (i += 1) {
        if (json_str[i] == '"' and json_str[i - 1] != '\\') {
            return json_str[content_begin..i];
        }
    }

    return null;
}
