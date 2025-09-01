const std = @import("std");
const builtin = @import("builtin");

pub const Account = struct {
    name: []const u8,
};

pub const AccountStore = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn getConfigRoot(self: *Self) ![]u8 {
        // Cross-platform config root:
        // - Windows: %APPDATA%\zigchat (fall back to %USERPROFILE%\.zigchat)
        // - Others:  $HOME/.zigchat
        var gpa = std.heap.page_allocator;
        if (builtin.os.tag == .windows) {
            if (std.process.getEnvVarOwned(gpa, "APPDATA")) |appdata| {
                defer gpa.free(appdata);
                const p = try std.fs.path.join(gpa, &[_][]const u8{ appdata, "zigchat" });
                defer gpa.free(p);
                return try self.allocator.dupe(u8, p);
            } else |_| {
                if (std.process.getEnvVarOwned(gpa, "USERPROFILE")) |home| {
                    defer gpa.free(home);
                    const p = try std.fs.path.join(gpa, &[_][]const u8{ home, ".zigchat" });
                    defer gpa.free(p);
                    return try self.allocator.dupe(u8, p);
                } else |_| {
                    return error.EnvNotFound;
                }
            }
        } else {
            if (std.process.getEnvVarOwned(gpa, "HOME")) |home| {
                defer gpa.free(home);
                const p = try std.fs.path.join(gpa, &[_][]const u8{ home, ".zigchat" });
                defer gpa.free(p);
                return try self.allocator.dupe(u8, p);
            } else |_| {
                return error.EnvNotFound;
            }
        }
    }

    fn getKeysDir(self: *Self) ![]u8 {
        const base = try self.getConfigRoot();
        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ base, "keys" });
        self.allocator.free(base);
        return path;
    }

    pub fn ensureDirs(self: *Self) !void {
        const base = try self.getConfigRoot();
        defer self.allocator.free(base);
        std.fs.makeDirAbsolute(base) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const keys = try self.getKeysDir();
        defer self.allocator.free(keys);
        std.fs.makeDirAbsolute(keys) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    pub fn listAccounts(self: *Self) !std.ArrayList(Account) {
        try self.ensureDirs();

        var list = std.ArrayList(Account).init(self.allocator);
        const keys_dir_path = try self.getKeysDir();
        defer self.allocator.free(keys_dir_path);

        var dir = std.fs.openDirAbsolute(keys_dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return list, // empty
            else => return err,
        };
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            // Only include *.key files
            if (!std.mem.endsWith(u8, entry.name, ".key")) continue;
            const name_no_ext = entry.name[0 .. entry.name.len - 4];
            const name_copy = try self.allocator.dupe(u8, name_no_ext);
            try list.append(.{ .name = name_copy });
        }

        return list;
    }

    pub fn loadPrivateKeyHex(self: *Self, name: []const u8) ![]u8 {
        const keys_dir = try self.getKeysDir();
        defer self.allocator.free(keys_dir);
        const filename = try std.fs.path.join(self.allocator, &[_][]const u8{ keys_dir, try self.withKeyExt(name) });
        defer self.allocator.free(filename);

        const file = try std.fs.openFileAbsolute(filename, .{});
        defer file.close();
        const data = try file.readToEndAlloc(self.allocator, 128);
        defer self.allocator.free(data);
        // Trim whitespace/newlines and return a copy owned by caller
        const trimmed = std.mem.trim(u8, data, " \t\r\n");
        return try self.allocator.dupe(u8, trimmed);
    }

    pub fn savePrivateKeyHex(self: *Self, name: []const u8, priv_hex: []const u8) !void {
        try self.ensureDirs();
        const keys_dir = try self.getKeysDir();
        defer self.allocator.free(keys_dir);
        const filename = try std.fs.path.join(self.allocator, &[_][]const u8{ keys_dir, try self.withKeyExt(name) });
        defer self.allocator.free(filename);

        var file = try std.fs.createFileAbsolute(filename, .{ .truncate = true });
        defer file.close();
        _ = try file.writeAll(priv_hex);
        _ = try file.writeAll("\n");
    }

    fn withKeyExt(self: *Self, name: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}.key", .{name});
    }

    pub fn sanitizeName(self: *Self, name: []const u8) ![]u8 {
        // Replace spaces with underscores and remove slashes
        var buf = try self.allocator.alloc(u8, name.len);
        var j: usize = 0;
        for (name) |c| {
            if (c == '/' or c == '\\' or c == ':' or c == 0) continue;
            buf[j] = if (c == ' ') '_' else c;
            j += 1;
        }
        return buf[0..j];
    }

    pub fn accountExists(self: *Self, name: []const u8) bool {
        const keys_dir = self.getKeysDir() catch return false;
        defer self.allocator.free(keys_dir);
        const filename = std.fs.path.join(self.allocator, &[_][]const u8{ keys_dir, self.withKeyExt(name) catch return false }) catch return false;
        defer self.allocator.free(filename);
        const file = std.fs.openFileAbsolute(filename, .{}) catch return false;
        file.close();
        return true;
    }
};
