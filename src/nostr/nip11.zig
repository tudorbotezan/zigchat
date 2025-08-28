const std = @import("std");
const http_client = @import("../http_client.zig");

pub const RelayInfo = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    pubkey: ?[]const u8 = null,
    contact: ?[]const u8 = null,
    supported_nips: ?[]u32 = null,
    software: ?[]const u8 = null,
    version: ?[]const u8 = null,
    auth_required: bool = false,
    payment_required: bool = false,
    restricted_writes: bool = false,
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
    };
};

pub fn fetchRelayInfo(allocator: std.mem.Allocator, relay_url: []const u8) !RelayInfo {
    // Try to fetch NIP-11 info via HTTP
    const json = http_client.fetchRelayInfo(allocator, relay_url) catch |err| {
        std.debug.print("[{s}] Failed to fetch NIP-11 info: {}\n", .{ relay_url, err });
        // Return default info if fetch fails
        return RelayInfo{};
    };
    defer allocator.free(json);
    
    const info = try http_client.parseRelayInfo(allocator, json);
    
    std.debug.print("[{s}] NIP-11: auth_required={}, restricted_writes={}\n", .{ 
        relay_url, 
        info.auth_required, 
        info.restricted_writes 
    });
    
    return RelayInfo{
        .name = info.name,
        .description = info.description,
        .auth_required = info.auth_required,
        .payment_required = info.payment_required,
        .restricted_writes = info.restricted_writes,
    };
}
