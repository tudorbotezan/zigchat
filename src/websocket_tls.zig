const std = @import("std");
const ws = @import("ws");
const net = std.net;
const tls = std.crypto.tls;

pub const TlsWebSocketClient = struct {
    allocator: std.mem.Allocator,
    tcp_stream: ?net.Stream = null,
    tls_client: ?*tls.Client = null,
    ws_stream: ?ws.stream.Stream(TlsReader, TlsWriter) = null,
    connected: bool = false,
    url: []const u8,

    const Self = @This();

    // Wrapper types for TLS reader/writer
    const TlsReader = struct {
        tls_client: *tls.Client,
        tcp_stream: net.Stream,

        pub const Error = anyerror; // Use generic error for now

        pub fn read(self: TlsReader, buffer: []u8) Error!usize {
            return self.tls_client.read(self.tcp_stream, buffer);
        }

        pub fn readByte(self: TlsReader) !u8 {
            var byte: [1]u8 = undefined;
            const n = try self.read(&byte);
            if (n == 0) return error.EndOfStream;
            return byte[0];
        }

        pub fn readUntilDelimiterAlloc(
            self: TlsReader,
            allocator: std.mem.Allocator,
            delimiter: u8,
            max_size: usize,
        ) ![]u8 {
            var array_list = std.ArrayList(u8).init(allocator);
            defer array_list.deinit();

            while (array_list.items.len < max_size) {
                const byte = try self.readByte();

                if (byte == delimiter) {
                    break;
                }

                try array_list.append(byte);
            }

            return array_list.toOwnedSlice();
        }
    };

    const TlsWriter = struct {
        tls_client: *tls.Client,
        tcp_stream: net.Stream,

        pub const Error = anyerror; // Use generic error for now

        pub fn write(self: TlsWriter, buffer: []const u8) Error!usize {
            return self.tls_client.write(self.tcp_stream, buffer);
        }

        pub fn writeAll(self: TlsWriter, buffer: []const u8) Error!void {
            return self.tls_client.writeAll(self.tcp_stream, buffer);
        }
    };

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
            .percent_encoded => |h| h,
        };
        const port: u16 = uri.port orelse 443;

        std.debug.print("Connecting to {s}:{d} with TLS...\n", .{ host, port });

        // Connect TCP
        self.tcp_stream = try net.tcpConnectToHost(self.allocator, host, port);
        errdefer {
            if (self.tcp_stream) |tcp| {
                tcp.close();
                self.tcp_stream = null;
            }
        }
        
        // Set socket to non-blocking mode for better message streaming
        const sock_flags = try std.posix.fcntl(self.tcp_stream.?.handle, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(self.tcp_stream.?.handle, std.posix.F.SETFL, sock_flags | std.posix.O.NONBLOCK);

        // Create TLS client
        self.tls_client = try self.allocator.create(tls.Client);
        errdefer {
            if (self.tls_client) |client| {
                self.allocator.destroy(client);
                self.tls_client = null;
            }
        }

        // Initialize TLS client with proper options
        const tls_options = tls.Client.Options{
            .host = .{ .explicit = host },
            .ca = .no_verification, // For now, skip CA verification for testing
        };

        self.tls_client.?.* = tls.Client.init(self.tcp_stream.?, tls_options) catch |err| {
            std.debug.print("TLS init error: {}\n", .{err});
            return err;
        };

        // Create readers/writers for WebSocket
        const tls_reader = TlsReader{
            .tls_client = self.tls_client.?,
            .tcp_stream = self.tcp_stream.?,
        };
        const tls_writer = TlsWriter{
            .tls_client = self.tls_client.?,
            .tcp_stream = self.tcp_stream.?,
        };

        // Perform WebSocket handshake
        self.ws_stream = try ws.client(
            self.allocator,
            tls_reader,
            tls_writer,
            self.url,
        );

        self.connected = true;
        std.debug.print("TLS WebSocket connected!\n", .{});
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

        // Try to receive with non-blocking behavior
        if (self.ws_stream.?.nextMessage()) |msg| {
            defer msg.deinit();

            if (msg.encoding == .text) {
                const text_copy = try self.allocator.dupe(u8, msg.payload);
                return text_copy;
            }
        } else |err| {
            // Handle non-blocking socket errors
            if (err == error.WouldBlock or err == error.Again) {
                return null; // No data available right now
            }
            return err; // Real error
        }

        if (self.ws_stream.?.err) |err| {
            // Don't print WouldBlock errors - they're expected in non-blocking mode
            if (err != error.WouldBlock and err != error.Again) {
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

        if (self.tls_client) |client| {
            // TLS Client doesn't have explicit deinit, just destroy the allocation
            self.allocator.destroy(client);
            self.tls_client = null;
        }

        if (self.tcp_stream) |tcp| {
            tcp.close();
            self.tcp_stream = null;
        }

        self.connected = false;
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }
};
