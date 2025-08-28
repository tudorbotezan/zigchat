const std = @import("std");
const nostr = @import("nostr/client.zig");
const store = @import("store/config.zig");

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
            std.debug.print("Usage: bitchat auth test\n", .{});
        }
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Bitchat - Minimal Nostr TUI Client
        \\
        \\Usage:
        \\  bitchat keygen                  Generate new keypair
        \\  bitchat whoami                  Show current identity
        \\  bitchat relay add <url>         Add relay
        \\  bitchat relay ls                List relays
        \\  bitchat relay rm <index>        Remove relay
        \\  bitchat pub <message>           Publish note
        \\  bitchat sub [options]           Subscribe to notes
        \\  bitchat auth test               Test AUTH flow
        \\
    , .{});
}

fn printRelayUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage:
        \\  bitchat relay add <url>    Add a relay
        \\  bitchat relay ls           List all relays
        \\  bitchat relay rm <index>   Remove relay by index
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
