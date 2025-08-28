const std = @import("std");
const NostrMessage = @import("nostr_ws_client.zig").NostrMessage;

/// Thread-safe message queue for buffering messages from relays
pub const MessageQueue = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(QueuedMessage),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    max_size: usize = 1000,

    pub const QueuedMessage = struct {
        message: NostrMessage,
        relay_url: []const u8,
        received_at: i64,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .messages = std.ArrayList(QueuedMessage).init(allocator),
            .mutex = .{},
            .condition = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        for (self.messages.items) |*item| {
            item.message.deinit();
            self.allocator.free(item.relay_url);
        }
        self.messages.deinit();
    }

    /// Add a message to the queue (thread-safe)
    pub fn push(self: *Self, message: NostrMessage, relay_url: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Drop oldest messages if queue is full
        if (self.messages.items.len >= self.max_size) {
            const oldest = self.messages.orderedRemove(0);
            oldest.message.deinit();
            self.allocator.free(oldest.relay_url);
        }

        const queued_msg = QueuedMessage{
            .message = message,
            .relay_url = try self.allocator.dupe(u8, relay_url),
            .received_at = std.time.timestamp(),
        };

        try self.messages.append(queued_msg);
        
        // Signal waiting threads
        self.condition.signal();
    }

    /// Get the next message from the queue (thread-safe, blocking)
    pub fn pop(self: *Self) ?QueuedMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.messages.items.len == 0) {
            return null;
        }

        return self.messages.orderedRemove(0);
    }

    /// Get the next message from the queue with timeout (thread-safe)
    pub fn popWithTimeout(self: *Self, timeout_ns: u64) ?QueuedMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        
        while (self.messages.items.len == 0) {
            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed >= timeout_ns) {
                return null;
            }
            
            const remaining = timeout_ns - @as(u64, @intCast(elapsed));
            self.condition.timedWait(&self.mutex, remaining) catch {
                return null;
            };
        }

        return self.messages.orderedRemove(0);
    }

    /// Check if queue is empty (thread-safe)
    pub fn isEmpty(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.messages.items.len == 0;
    }

    /// Get queue size (thread-safe)
    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.messages.items.len;
    }

    /// Sort messages by timestamp (thread-safe)
    pub fn sortByTimestamp(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const Context = struct {
            pub fn lessThan(_: @This(), a: QueuedMessage, b: QueuedMessage) bool {
                // First sort by created_at if available
                if (a.message.created_at != null and b.message.created_at != null) {
                    return a.message.created_at.? < b.message.created_at.?;
                }
                // Fall back to received_at timestamp
                return a.received_at < b.received_at;
            }
        };

        std.sort.pdq(QueuedMessage, self.messages.items, Context{}, Context.lessThan);
    }
};