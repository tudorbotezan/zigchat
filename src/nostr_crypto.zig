const std = @import("std");
const crypto = std.crypto;
const secp = @import("secp256k1.zig");

pub const KeyPair = struct {
    private_key: [32]u8,
    public_key: [32]u8,
    
    pub fn generate() !KeyPair {
        var ctx = try secp.Secp256k1.init();
        defer ctx.deinit();
        
        const private_key = try ctx.generateKeypair();
        const public_key = try ctx.getPublicKey(private_key);
        
        return .{
            .private_key = private_key,
            .public_key = public_key,
        };
    }
    
    pub fn fromHex(private_key_hex: []const u8) !KeyPair {
        var private_key: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&private_key, private_key_hex);
        
        var ctx = try secp.Secp256k1.init();
        defer ctx.deinit();
        
        const public_key = try ctx.getPublicKey(private_key);
        
        return .{
            .private_key = private_key,
            .public_key = public_key,
        };
    }
};

pub fn serializeEvent(
    pubkey: []const u8,
    created_at: i64,
    kind: u32,
    tags: []const []const []const u8,
    content: []const u8,
    allocator: std.mem.Allocator
) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try buffer.append('[');
    try buffer.append('0');
    try buffer.append(',');
    
    // pubkey
    try buffer.append('"');
    try buffer.appendSlice(pubkey);
    try buffer.append('"');
    try buffer.append(',');
    
    // created_at
    try std.fmt.format(buffer.writer(), "{d}", .{created_at});
    try buffer.append(',');
    
    // kind
    try std.fmt.format(buffer.writer(), "{d}", .{kind});
    try buffer.append(',');
    
    // tags
    try buffer.append('[');
    for (tags, 0..) |tag, i| {
        if (i > 0) try buffer.append(',');
        try buffer.append('[');
        for (tag, 0..) |value, j| {
            if (j > 0) try buffer.append(',');
            try buffer.append('"');
            // Escape the value
            for (value) |c| {
                switch (c) {
                    '"' => try buffer.appendSlice("\\\""),
                    '\\' => try buffer.appendSlice("\\\\"),
                    '\n' => try buffer.appendSlice("\\n"),
                    '\r' => try buffer.appendSlice("\\r"),
                    '\t' => try buffer.appendSlice("\\t"),
                    else => try buffer.append(c),
                }
            }
            try buffer.append('"');
        }
        try buffer.append(']');
    }
    try buffer.append(']');
    try buffer.append(',');
    
    // content
    try buffer.append('"');
    for (content) |c| {
        switch (c) {
            '"' => try buffer.appendSlice("\\\""),
            '\\' => try buffer.appendSlice("\\\\"),
            '\n' => try buffer.appendSlice("\\n"),
            '\r' => try buffer.appendSlice("\\r"),
            '\t' => try buffer.appendSlice("\\t"),
            else => try buffer.append(c),
        }
    }
    try buffer.append('"');
    
    try buffer.append(']');
    
    return buffer.toOwnedSlice();
}

pub fn computeEventId(serialized: []const u8) [32]u8 {
    var hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(serialized, &hash, .{});
    return hash;
}

pub fn signEvent(event_id: [32]u8, private_key: [32]u8) ![64]u8 {
    var ctx = try secp.Secp256k1.init();
    defer ctx.deinit();
    
    return try ctx.signSchnorr(event_id, private_key);
}

pub const NostrEvent = struct {
    id: [64]u8, // hex string
    pubkey: [64]u8, // hex string
    created_at: i64,
    kind: u32,
    tags: []const []const []const u8,
    content: []const u8,
    sig: [128]u8, // hex string
    
    pub fn create(
        keypair: KeyPair,
        kind: u32,
        tags: []const []const []const u8,
        content: []const u8,
        allocator: std.mem.Allocator
    ) !NostrEvent {
        const created_at = std.time.timestamp();
        
        // Convert pubkey to hex
        var pubkey_hex: [64]u8 = undefined;
        _ = try std.fmt.bufPrint(&pubkey_hex, "{}", .{std.fmt.fmtSliceHexLower(&keypair.public_key)});
        
        // Serialize event for hashing
        const serialized = try serializeEvent(&pubkey_hex, created_at, kind, tags, content, allocator);
        defer allocator.free(serialized);
        
        // Compute event ID
        const event_id = computeEventId(serialized);
        var id_hex: [64]u8 = undefined;
        _ = try std.fmt.bufPrint(&id_hex, "{}", .{std.fmt.fmtSliceHexLower(&event_id)});
        
        // Sign the event
        const signature = try signEvent(event_id, keypair.private_key);
        var sig_hex: [128]u8 = undefined;
        _ = try std.fmt.bufPrint(&sig_hex, "{}", .{std.fmt.fmtSliceHexLower(&signature)});
        
        return NostrEvent{
            .id = id_hex,
            .pubkey = pubkey_hex,
            .created_at = created_at,
            .kind = kind,
            .tags = tags,
            .content = content,
            .sig = sig_hex,
        };
    }
    
    pub fn toJson(self: *const NostrEvent, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.append('{');
        
        // id
        try buffer.appendSlice("\"id\":\"");
        try buffer.appendSlice(&self.id);
        try buffer.appendSlice("\",");
        
        // pubkey
        try buffer.appendSlice("\"pubkey\":\"");
        try buffer.appendSlice(&self.pubkey);
        try buffer.appendSlice("\",");
        
        // created_at
        try std.fmt.format(buffer.writer(), "\"created_at\":{d},", .{self.created_at});
        
        // kind
        try std.fmt.format(buffer.writer(), "\"kind\":{d},", .{self.kind});
        
        // tags
        try buffer.appendSlice("\"tags\":[");
        for (self.tags, 0..) |tag, i| {
            if (i > 0) try buffer.append(',');
            try buffer.append('[');
            for (tag, 0..) |value, j| {
                if (j > 0) try buffer.append(',');
                try buffer.append('"');
                for (value) |c| {
                    switch (c) {
                        '"' => try buffer.appendSlice("\\\""),
                        '\\' => try buffer.appendSlice("\\\\"),
                        '\n' => try buffer.appendSlice("\\n"),
                        '\r' => try buffer.appendSlice("\\r"),
                        '\t' => try buffer.appendSlice("\\t"),
                        else => try buffer.append(c),
                    }
                }
                try buffer.append('"');
            }
            try buffer.append(']');
        }
        try buffer.appendSlice("],");
        
        // content
        try buffer.appendSlice("\"content\":\"");
        for (self.content) |c| {
            switch (c) {
                '"' => try buffer.appendSlice("\\\""),
                '\\' => try buffer.appendSlice("\\\\"),
                '\n' => try buffer.appendSlice("\\n"),
                '\r' => try buffer.appendSlice("\\r"),
                '\t' => try buffer.appendSlice("\\t"),
                else => try buffer.append(c),
            }
        }
        try buffer.appendSlice("\",");
        
        // sig
        try buffer.appendSlice("\"sig\":\"");
        try buffer.appendSlice(&self.sig);
        try buffer.appendSlice("\"}");
        
        return buffer.toOwnedSlice();
    }
};