const std = @import("std");

pub const KVStore = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]u8),
    file_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) KVStore {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap([]u8).init(allocator),
            .file_path = file_path,
        };
    }

    pub fn deinit(self: *KVStore) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn put(self: *KVStore, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);

        if (self.data.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        try self.data.put(key_copy, value_copy);
    }

    pub fn get(self: *KVStore, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn delete(self: *KVStore, key: []const u8) void {
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }

    pub fn save(self: *KVStore) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{});
        defer file.close();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            try file.writer().print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    pub fn load(self: *KVStore) !void {
        const file = std.fs.openFileAbsolute(self.file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.tokenize(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = line[0..eq_pos];
                const value = line[eq_pos + 1 ..];
                try self.put(key, value);
            }
        }
    }
};
