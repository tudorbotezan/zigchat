const std = @import("std");

pub const RelayInfo = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    pubkey: ?[]const u8 = null,
    contact: ?[]const u8 = null,
    supported_nips: ?[]u32 = null,
    software: ?[]const u8 = null,
    version: ?[]const u8 = null,
    limitation: ?Limitation = null,

    pub const Limitation = struct {
        max_message_length: ?u32 = null,
        max_subscriptions: ?u32 = null,
        max_filters: ?u32 = null,
        max_limit: ?u32 = null,
        max_subid_length: ?u32 = null,
        max_event_tags: ?u32 = null,
        max_content_length: ?u32 = null,
        min_pow_difficulty: ?u32 = null,
        auth_required: ?bool = null,
        payment_required: ?bool = null,
        restricted_writes: ?bool = null,
    };
};

pub fn fetchRelayInfo(allocator: std.mem.Allocator, relay_url: []const u8) !RelayInfo {
    _ = allocator;
    _ = relay_url;
    std.debug.print("TODO: Fetch NIP-11 relay information document\n", .{});
    return RelayInfo{};
}
