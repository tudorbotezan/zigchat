const std = @import("std");

pub const Config = struct {
    keys: ?Keys = null,
    relays: []Relay = &[_]Relay{},
    prefs: Preferences = .{},

    pub const Keys = struct {
        sk_hex: []const u8,
        pk_hex: []const u8,
    };

    pub const Relay = struct {
        url: []const u8,
        read: bool = true,
        write: bool = true,
    };

    pub const Preferences = struct {
        timeout_ms: u32 = 8000,
        max_inflight: u32 = 2,
    };
};

pub fn getConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.os.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fmt.allocPrint(allocator, "{s}/.config/zigchat/config.json", .{home});
}

pub fn load(allocator: std.mem.Allocator) !Config {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return Config{},
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(Config, allocator, content, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return parsed.value;
}

pub fn save(allocator: std.mem.Allocator, config: Config) !void {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    try std.fs.makeDirAbsolute(config_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const file = try std.fs.createFileAbsolute(config_path, .{});
    defer file.close();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try std.json.stringify(config, .{ .whitespace = .indent_2 }, array_list.writer());
    try file.writeAll(array_list.items);
}

pub fn addRelay(allocator: std.mem.Allocator, url: []const u8) !void {
    var config = try load(allocator);

    var new_relays = try allocator.alloc(Config.Relay, config.relays.len + 1);
    defer allocator.free(new_relays);

    for (config.relays, 0..) |relay, i| {
        new_relays[i] = relay;
    }
    new_relays[config.relays.len] = .{
        .url = url,
        .read = true,
        .write = true,
    };

    config.relays = new_relays;
    try save(allocator, config);
}

pub fn removeRelay(allocator: std.mem.Allocator, index: usize) !void {
    var config = try load(allocator);

    if (index >= config.relays.len) {
        return error.IndexOutOfBounds;
    }

    var new_relays = try allocator.alloc(Config.Relay, config.relays.len - 1);
    defer allocator.free(new_relays);

    var j: usize = 0;
    for (config.relays, 0..) |relay, i| {
        if (i != index) {
            new_relays[j] = relay;
            j += 1;
        }
    }

    config.relays = new_relays;
    try save(allocator, config);
}
