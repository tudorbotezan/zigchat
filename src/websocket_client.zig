const std = @import("std");
const ws = @import("ws");
const net = std.net;

pub const WebSocketClient = struct {
    allocator: std.mem.Allocator,
    tcp_client: ?net.Stream = null,
    ws_stream: ?ws.stream.Stream(net.Stream.Reader, net.Stream.Writer) = null,
    connected: bool = false,
    url: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, url: []const u8) Self {
        return .{
            .allocator = allocator,
            .url = url,
        };
    }

    pub fn connect(self: *Self) !void {
        const uri = try std.Uri.parse(self.url);
        const host_component = uri.host orelse return error.InvalidUrl;
        const host = switch (host_component) {
            .raw => |h| h,
            .percent_encoded => |h| h, // Should decode, but for now just use it
        };
        const port: u16 = if (uri.port) |p| p else blk: {
            if (std.mem.eql(u8, uri.scheme, "wss")) {
                break :blk @as(u16, 443);
            } else if (std.mem.eql(u8, uri.scheme, "ws")) {
                break :blk @as(u16, 80);
            } else {
                return error.UnsupportedScheme;
            }
        };

        std.debug.print("Connecting to {s}:{d}...\n", .{ host, port });

        // Connect TCP
        self.tcp_client = try net.tcpConnectToHost(self.allocator, host, port);
        errdefer if (self.tcp_client) |tcp| tcp.close();

        const is_tls = std.mem.eql(u8, uri.scheme, "wss");

        if (is_tls) {
            // For now, we'll skip TLS and focus on non-TLS connections
            std.debug.print("TLS support coming soon. Use ws:// for now.\n", .{});
            return error.TlsNotImplemented;
        }

        // Perform WebSocket handshake
        const tcp = self.tcp_client.?;
        self.ws_stream = try ws.client(
            self.allocator,
            tcp.reader(),
            tcp.writer(),
            self.url,
        );

        self.connected = true;
        std.debug.print("WebSocket connected!\n", .{});
        
        // Now set socket to non-blocking mode after handshake is complete
        const sock_flags = try std.posix.fcntl(self.tcp_client.?.handle, std.posix.F.GETFL, 0);
        const nonblock_flag = if (@hasDecl(std.posix.O, "NONBLOCK")) std.posix.O.NONBLOCK else 0x0004; // O_NONBLOCK on macOS
        _ = try std.posix.fcntl(self.tcp_client.?.handle, std.posix.F.SETFL, sock_flags | nonblock_flag);
    }

    pub fn sendText(self: *Self, text: []const u8) !void {
        if (!self.connected or self.ws_stream == null) {
            return error.NotConnected;
        }

        const message = ws.Message{
            .encoding = .text,
            .payload = text,
        };

        try self.ws_stream.?.sendMessage(message);
        // Don't print sent messages - let higher level code handle that
    }

    pub fn receive(self: *Self) !?[]const u8 {
        if (!self.connected or self.ws_stream == null) {
            return error.NotConnected;
        }

        // nextMessage() returns ?Message, not an error union
        if (self.ws_stream.?.nextMessage()) |msg| {
            defer msg.deinit();

            if (msg.encoding == .text) {
                const text_copy = try self.allocator.dupe(u8, msg.payload);
                return text_copy;
            }
        }

        // Check for errors on the stream
        if (self.ws_stream.?.err) |err| {
            // Handle non-blocking socket errors
            if (err == error.WouldBlock or err == error.Again) {
                return null; // No data available right now
            }
            // Don't print expected errors:
            // - WouldBlock/Again: expected in non-blocking mode
            // - TlsConnectionTruncated: normal disconnection
            // - ReservedOpcode: protocol-level error that doesn't affect functionality
            if (err != error.WouldBlock and err != error.Again and err != error.TlsConnectionTruncated and err != error.ReservedOpcode) {
                std.debug.print("WebSocket error: {}\n", .{err});
            }
            return err;
        }

        return null;
    }

    pub fn close(self: *Self) void {
        if (self.ws_stream) |*stream| {
            stream.deinit();
            self.ws_stream = null;
        }

        if (self.tcp_client) |tcp| {
            tcp.close();
            self.tcp_client = null;
        }

        self.connected = false;
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }
};
