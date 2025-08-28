const std = @import("std");

pub fn fetchRelayInfo(allocator: std.mem.Allocator, relay_url: []const u8) ![]u8 {
    // For now, return a mock response since HTTP client in Zig is complex
    // In production, you'd use curl or a proper HTTP library
    _ = relay_url;
    
    // Return empty JSON for now - relay will work with defaults
    const mock_response = try allocator.dupe(u8, "{}");
    return mock_response;
}

pub fn parseRelayInfo(allocator: std.mem.Allocator, json: []const u8) !RelayInfo {
    var info = RelayInfo{};
    
    // Simple JSON parsing for the fields we care about
    if (findJsonBoolValue(json, "auth_required")) |val| {
        info.auth_required = val;
    }
    
    if (findJsonBoolValue(json, "payment_required")) |val| {
        info.payment_required = val;
    }
    
    if (findJsonBoolValue(json, "restricted_writes")) |val| {
        info.restricted_writes = val;
    }
    
    if (findJsonStringValue(json, "name", allocator)) |val| {
        info.name = val;
    }
    
    if (findJsonStringValue(json, "description", allocator)) |val| {
        info.description = val;
    }
    
    return info;
}

pub const RelayInfo = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    auth_required: bool = false,
    payment_required: bool = false,
    restricted_writes: bool = false,
};

fn findJsonBoolValue(json: []const u8, key: []const u8) ?bool {
    var needle_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\"", .{key}) catch return null;
    
    const pos = std.mem.indexOf(u8, json, needle) orelse return null;
    var i = pos + needle.len;
    
    // Skip whitespace and colon
    while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != ':') return null;
    i += 1;
    while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
    
    // Check for true/false
    if (i + 4 <= json.len and std.mem.eql(u8, json[i..i+4], "true")) {
        return true;
    } else if (i + 5 <= json.len and std.mem.eql(u8, json[i..i+5], "false")) {
        return false;
    }
    
    return null;
}

fn findJsonStringValue(json: []const u8, key: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    var needle_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\"", .{key}) catch return null;
    
    const pos = std.mem.indexOf(u8, json, needle) orelse return null;
    var i = pos + needle.len;
    
    // Skip to the string value
    while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != ':') return null;
    i += 1;
    while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
    
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\' and i + 1 < json.len) i += 1; // Skip escaped chars
    }
    
    if (i >= json.len) return null;
    
    return allocator.dupe(u8, json[start..i]) catch null;
}