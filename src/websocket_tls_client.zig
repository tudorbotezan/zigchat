const std = @import("std");
const ws = @import("ws");
const net = std.net;

// Simplified TLS WebSocket client using a different approach
pub const WebSocketTlsClient = struct {
    allocator: std.mem.Allocator,
    tcp_stream: ?net.Stream = null,
    tls_client: ?std.crypto.tls.Client = null,
    ws_stream: ?*anyopaque = null, // Will hold the ws stream
    connected: bool = false,
    url: []const u8,
    reader_buf: [8192]u8 = undefined,
    writer_buf: [8192]u8 = undefined,

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
            .percent_encoded => |h| h,
        };

        const port: u16 = uri.port orelse blk: {
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
        self.tcp_stream = try net.tcpConnectToHost(self.allocator, host, port);
        errdefer if (self.tcp_stream) |tcp| tcp.close();

        const is_tls = std.mem.eql(u8, uri.scheme, "wss");

        if (is_tls) {
            std.debug.print("Initializing TLS...\n", .{});

            // Initialize TLS client with proper options
            const tcp = self.tcp_stream.?;
            self.tls_client = std.crypto.tls.Client.init(tcp, .{
                .host = .{ .explicit = host },
                .ca_bundle = null,
                .max_cipher_suite_tag = .tls_1_3,
            }) catch |err| {
                std.debug.print("TLS init failed: {}\n", .{err});
                return err;
            };

            // Create a TLS stream wrapper
            var tls_stream = TlsStream{
                .tls_client = &self.tls_client.?,
                .tcp_stream = tcp,
            };

            // Perform WebSocket handshake over TLS
            const ws_client = try ws.client(
                self.allocator,
                tls_stream.reader(),
                tls_stream.writer(),
                self.url,
            );

            // Store the ws client (we'll need to properly type this later)
            self.ws_stream = @ptrCast(ws_client);
        } else {
            // Non-TLS WebSocket
            const tcp = self.tcp_stream.?;
            const ws_client = try ws.client(
                self.allocator,
                tcp.reader(),
                tcp.writer(),
                self.url,
            );
            self.ws_stream = @ptrCast(ws_client);
        }

        self.connected = true;
        std.debug.print("WebSocket connected!\n", .{});
    }

    pub fn sendText(self: *Self, text: []const u8) !void {
        if (!self.connected) {
            return error.NotConnected;
        }

        // For now, just print what we would send
        std.debug.print("Would send: {s}\n", .{text});
    }

    pub fn receive(self: *Self) !?[]const u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        // Placeholder
        return null;
    }

    pub fn close(self: *Self) void {
        if (self.tls_client) |*client| {
            client.deinit();
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

// TLS Stream wrapper that provides reader/writer interface
const TlsStream = struct {
    tls_client: *std.crypto.tls.Client,
    tcp_stream: net.Stream,

    pub fn reader(self: *TlsStream) TlsReader {
        return TlsReader{ .tls_client = self.tls_client };
    }

    pub fn writer(self: *TlsStream) TlsWriter {
        return TlsWriter{ .tls_client = self.tls_client };
    }
};

const TlsReader = struct {
    tls_client: *std.crypto.tls.Client,

    pub fn read(self: TlsReader, buf: []u8) !usize {
        return self.tls_client.read(buf);
    }
};

const TlsWriter = struct {
    tls_client: *std.crypto.tls.Client,

    pub fn write(self: TlsWriter, buf: []const u8) !usize {
        try self.tls_client.writeAll(buf);
        return buf.len;
    }
};
