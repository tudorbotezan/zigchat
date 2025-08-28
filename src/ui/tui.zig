const std = @import("std");

pub const TUI = struct {
    allocator: std.mem.Allocator,
    running: bool = false,
    relay_status: []const u8 = "",
    timeline: std.ArrayList([]const u8),
    input_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) TUI {
        return .{
            .allocator = allocator,
            .timeline = std.ArrayList([]const u8).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *TUI) void {
        for (self.timeline.items) |msg| {
            self.allocator.free(msg);
        }
        self.timeline.deinit();
        self.input_buffer.deinit();
    }

    pub fn start(self: *TUI) !void {
        self.running = true;
        try self.clearScreen();
        try self.render();
    }

    pub fn stop(self: *TUI) void {
        self.running = false;
        self.clearScreen() catch {};
    }

    pub fn addMessage(self: *TUI, message: []const u8) !void {
        const msg_copy = try self.allocator.dupe(u8, message);
        try self.timeline.append(msg_copy);

        if (self.timeline.items.len > 100) {
            const old_msg = self.timeline.orderedRemove(0);
            self.allocator.free(old_msg);
        }
    }

    pub fn setRelayStatus(self: *TUI, status: []const u8) void {
        self.relay_status = status;
    }

    pub fn render(self: *TUI) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("\x1b[H", .{});

        try stdout.print("=== Bitchat TUI ===\n", .{});
        try stdout.print("Relay Status: {s}\n", .{self.relay_status});
        try stdout.print("{s}\n", .{"-" ** 50});

        const display_start = if (self.timeline.items.len > 20) self.timeline.items.len - 20 else 0;
        for (self.timeline.items[display_start..]) |msg| {
            try stdout.print("{s}\n", .{msg});
        }

        try stdout.print("{s}\n", .{"-" ** 50});
        try stdout.print("> {s}", .{self.input_buffer.items});
    }

    pub fn handleInput(self: *TUI, input: u8) !?[]u8 {
        switch (input) {
            '\n', '\r' => {
                if (self.input_buffer.items.len > 0) {
                    const message = try self.allocator.dupe(u8, self.input_buffer.items);
                    self.input_buffer.clearRetainingCapacity();
                    return message;
                }
            },
            127, 8 => {
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            else => {
                if (input >= 32 and input < 127) {
                    try self.input_buffer.append(input);
                }
            },
        }
        return null;
    }

    fn clearScreen(self: *TUI) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[2J\x1b[H", .{});
    }
};
