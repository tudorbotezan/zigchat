const std = @import("std");
const nostr = @import("nostr_crypto.zig");
const secp = @import("secp256k1.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== NIP-01 Signature Test ===\n\n", .{});

    // Test with known private key (for reproducibility)
    const private_key_hex = "5a5e76b2e130470243e007dc03099f3700781183a700b87e58cb88e0a99ad304";
    
    std.debug.print("Private key: {s}\n", .{private_key_hex});
    
    // Create keypair from hex private key
    const keypair = try nostr.KeyPair.fromHex(private_key_hex);
    
    // Convert public key to hex for display
    var pubkey_hex: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&pubkey_hex, "{}", .{std.fmt.fmtSliceHexLower(&keypair.public_key)});
    std.debug.print("Public key:  {s}\n\n", .{pubkey_hex});

    // Create a test event
    const tags = [_][]const []const u8{};
    const content = "Hello from Zig with real secp256k1 Schnorr signatures!";
    
    const event = try nostr.NostrEvent.create(
        keypair,
        1, // kind 1 = text note
        &tags,
        content,
        allocator
    );

    // Convert to JSON
    const json = try event.toJson(allocator);
    defer allocator.free(json);

    std.debug.print("Generated NIP-01 Event:\n{s}\n\n", .{json});

    // Verify the signature
    std.debug.print("Verifying signature...\n", .{});
    
    var ctx = try secp.Secp256k1.init();
    defer ctx.deinit();
    
    // Parse signature from hex
    var signature: [64]u8 = undefined;
    _ = try std.fmt.hexToBytes(&signature, &event.sig);
    
    // Parse event ID from hex
    var event_id: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&event_id, &event.id);
    
    const is_valid = try ctx.verifySchnorr(signature, event_id, keypair.public_key);
    
    if (is_valid) {
        std.debug.print("✅ Signature is VALID!\n", .{});
        std.debug.print("\nThis event can be sent to any Nostr relay.\n", .{});
    } else {
        std.debug.print("❌ Signature is INVALID\n", .{});
    }
    
    std.debug.print("\n=== Test Complete ===\n", .{});
}