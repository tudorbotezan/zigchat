const std = @import("std");

pub const KeyPair = struct {
    secret_key: [32]u8,
    public_key: [32]u8,
};

pub fn generateKeyPair() !KeyPair {
    var secret_key: [32]u8 = undefined;
    std.crypto.random.bytes(&secret_key);

    const public_key = try derivePublicKey(secret_key);

    return KeyPair{
        .secret_key = secret_key,
        .public_key = public_key,
    };
}

pub fn derivePublicKey(secret_key: [32]u8) ![32]u8 {
    _ = secret_key;
    std.debug.print("TODO: Derive public key using secp256k1\n", .{});
    return [_]u8{0} ** 32;
}

pub fn schnorrSign(message: [32]u8, secret_key: [32]u8) ![64]u8 {
    _ = message;
    _ = secret_key;
    std.debug.print("TODO: BIP-340 Schnorr signature\n", .{});
    return [_]u8{0} ** 64;
}

pub fn schnorrVerify(message: [32]u8, public_key: [32]u8, signature: [64]u8) !bool {
    _ = message;
    _ = public_key;
    _ = signature;
    std.debug.print("TODO: BIP-340 signature verification\n", .{});
    return false;
}

pub fn toHex(bytes: []const u8, out: []u8) void {
    const charset = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        out[i * 2] = charset[byte >> 4];
        out[i * 2 + 1] = charset[byte & 0x0F];
    }
}

pub fn fromHex(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.InvalidLength;

    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = try charToNibble(hex[i * 2]);
        const lo = try charToNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn charToNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexChar,
    };
}
