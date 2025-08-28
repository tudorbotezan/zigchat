const std = @import("std");

pub fn serialize(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try std.json.stringify(value, .{}, array_list.writer());
    return array_list.toOwnedSlice();
}

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, json_str: []const u8) !T {
    const parsed = try std.json.parseFromSlice(T, allocator, json_str, .{});
    defer parsed.deinit();
    return parsed.value;
}

pub fn canonicalSerialize(allocator: std.mem.Allocator, event: anytype) ![]u8 {
    _ = allocator;
    _ = event;
    std.debug.print("TODO: NIP-01 canonical serialization\n", .{});
    return error.NotImplemented;
}
