const std = @import("std");
const crypto = std.crypto;

// For now, we'll use a simplified approach that at least generates proper format
// In production, you'd want to use a proper secp256k1 library like Zabi

pub const KeyPair = struct {
    private_key: [32]u8,
    public_key: [32]u8,
    
    pub fn generate() KeyPair {
        var private_key: [32]u8 = undefined;
        crypto.random.bytes(&private_key);
        
        // For demo: derive a deterministic "public key" from private
        // Real implementation needs proper secp256k1 scalar multiplication
        var public_key: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(&private_key, &public_key, .{});
        
        return .{
            .private_key = private_key,
            .public_key = public_key,
        };
    }
    
    pub fn fromHex(private_key_hex: []const u8) !KeyPair {
        var private_key: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&private_key, private_key_hex);
        
        var public_key: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(&private_key, &public_key, .{});
        
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

// Simplified "signing" for demo - generates deterministic but not cryptographically valid signature
// Real implementation needs proper Schnorr BIP-340
pub fn signEvent(event_id: [32]u8, private_key: [32]u8) [64]u8 {
    var sig: [64]u8 = undefined;
    
    // For demo: concatenate hashes to create a deterministic 64-byte value
    // Real implementation needs proper Schnorr signing
    var hasher = crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&event_id);
    hasher.update(&private_key);
    hasher.update("nostr_sign"); // Add domain separator
    
    var hash1: [32]u8 = undefined;
    hasher.final(&hash1);
    
    hasher = crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&hash1);
    hasher.update(&private_key);
    hasher.update("nostr_sig2");
    
    var hash2: [32]u8 = undefined;
    hasher.final(&hash2);
    
    @memcpy(sig[0..32], &hash1);
    @memcpy(sig[32..64], &hash2);
    
    return sig;
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
        const signature = signEvent(event_id, keypair.private_key);
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