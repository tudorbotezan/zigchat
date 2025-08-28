const std = @import("std");
const Event = @import("event.zig").Event;

pub const AuthChallenge = struct {
    relay: []const u8,
    challenge: []const u8,
};

pub fn createAuthEvent(
    allocator: std.mem.Allocator,
    challenge: AuthChallenge,
    pubkey: [64]u8,
    secret_key: [32]u8,
) !Event {
    _ = allocator;
    _ = secret_key;

    const tags = &[_][]const []const u8{
        &[_][]const u8{ "relay", challenge.relay },
        &[_][]const u8{ "challenge", challenge.challenge },
    };

    const event = Event.init(
        pubkey,
        22242,
        "",
        tags,
    );

    return event;
}

pub fn handleAuthRequest(allocator: std.mem.Allocator, auth_msg: []const u8) !AuthChallenge {
    _ = allocator;
    _ = auth_msg;
    std.debug.print("TODO: Parse AUTH challenge message\n", .{});
    return AuthChallenge{
        .relay = "",
        .challenge = "",
    };
}
