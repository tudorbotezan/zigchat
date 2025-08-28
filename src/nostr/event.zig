const std = @import("std");

pub const Event = struct {
    id: ?[64]u8 = null,
    pubkey: [64]u8,
    created_at: i64,
    kind: u32,
    tags: [][]const []const u8,
    content: []const u8,
    sig: ?[128]u8 = null,

    pub fn init(
        pubkey: [64]u8,
        kind: u32,
        content: []const u8,
        tags: [][]const []const u8,
    ) Event {
        return .{
            .pubkey = pubkey,
            .created_at = std.time.timestamp(),
            .kind = kind,
            .tags = tags,
            .content = content,
        };
    }

    pub fn computeId(self: *Event, allocator: std.mem.Allocator) ![64]u8 {
        _ = self;
        _ = allocator;
        std.debug.print("TODO: Compute event ID hash\n", .{});
        return [_]u8{0} ** 64;
    }

    pub fn sign(self: *Event, secret_key: [32]u8) ![128]u8 {
        _ = self;
        _ = secret_key;
        std.debug.print("TODO: Sign event with Schnorr\n", .{});
        return [_]u8{0} ** 128;
    }

    pub fn verify(self: Event) !bool {
        _ = self;
        std.debug.print("TODO: Verify event signature\n", .{});
        return false;
    }
};
