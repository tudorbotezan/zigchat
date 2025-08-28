const std = @import("std");
const ws = @import("ws");
const net = std.net;
const tls = std.crypto.tls;

pub const TlsWebSocketClient = struct {
    allocator: std.mem.Allocator,
    tcp_client: ?net.Stream = null,
    tls_client: ?*tls.Client = null,
    ws_stream: ?ws.stream.Stream(TlsReader, TlsWriter) = null,
    connected: bool = false,
    url: []const u8,

    const Self = @This();

    // TLS Reader wrapper
    const TlsReader = struct {
        tls_client: *tls.Client,

        pub const ReadError = tls.Client.ReadError || error{EndOfStream};
        pub const Reader = std.io.Reader(*TlsReader, ReadError, read);

        pub fn reader(self: *TlsReader) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *TlsReader, buf: []u8) ReadError!usize {
            return self.tls_client.read(buf) catch |err| switch (err) {
                error.ConnectionResetByPeer => return error.EndOfStream,
                else => return err,
            };
        }
    };

    // TLS Writer wrapper
    const TlsWriter = struct {
        tls_client: *tls.Client,

        pub const WriteError = tls.Client.WriteError;
        pub const Writer = std.io.Writer(*TlsWriter, WriteError, write);

        pub fn writer(self: *TlsWriter) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *TlsWriter, buf: []const u8) WriteError!usize {
            try self.tls_client.writeAll(buf);
            return buf.len;
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
        const use_tls = std.mem.eql(u8, uri.scheme, "wss");

        std.debug.print("Connecting to {s}:{d} (TLS: {})...\n", .{ host, port, use_tls });

        // Connect TCP
        self.tcp_client = try net.tcpConnectToHost(self.allocator, host, port);
        errdefer if (self.tcp_client) |tcp| tcp.close();

        if (use_tls) {
            // Create TLS client
            self.tls_client = try self.allocator.create(tls.Client);
            errdefer self.allocator.destroy(self.tls_client.?);

            self.tls_client.* = tls.Client.init(self.tcp_client.?, .{
                .host = host,
                .ca_bundle = null, // Use system CA bundle
                .max_cipher_suite = .tls13_aes_256_gcm_sha384,
            });

            // Perform TLS handshake
            try self.tls_client.?.handshake();
            std.debug.print("TLS handshake completed\n", .{});

            // Create reader and writer wrappers
            var tls_reader = TlsReader{ .tls_client = self.tls_client.? };
            var tls_writer = TlsWriter{ .tls_client = self.tls_client.? };

            // Perform WebSocket handshake over TLS
            self.ws_stream = try ws.client(
                self.allocator,
                tls_reader.reader(),
                tls_writer.writer(),
                self.url,
            );
        } else {
            // Non-TLS connection
            const tcp = self.tcp_client.?;
            self.ws_stream = try ws.client(
                self.allocator,
                tcp.reader(),
                tcp.writer(),
                self.url,
            );
        }

        self.connected = true;
        std.debug.print("WebSocket connected!\n", .{});
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

        if (self.ws_stream.?.nextMessage()) |msg| {
            defer msg.deinit();

            if (msg.encoding == .text) {
                const text_copy = try self.allocator.dupe(u8, msg.payload);
                return text_copy;
            }
        }

        if (self.ws_stream.?.err) |err| {
            std.debug.print("WebSocket error: {}\n", .{err});
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
            client.deinit();
            self.allocator.destroy(client);
            self.tls_client = null;
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
