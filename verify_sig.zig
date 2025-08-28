const std = @import("std");
const nostr = @import("src/nostr_crypto.zig");
const secp = @import("src/secp256k1.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // This is the event you just sent
    const event_json = 
        \\{"id":"69f9901ef54b4ca3552053dcd0d6c46d664ebcb1dc3db762e25fbea9146b68ac","pubkey":"c8ae68a084ba5eafcf247013928b3758c1d9ceab49987f333cc34b93c1ad0caa","created_at":1756349487,"kind":1,"tags":[["g","9q"]],"content":"[11111]: what up tusk","sig":"32373101ada75693751dab7eecca4d0bce0d61254ad1aee77245dc91e03f0d2e7044f682b3f7e31aa6efea1cf747564f47e145b013a6fc54a5ae172978202a4a"}
    ;
    
    std.debug.print("Verifying your event:\n{s}\n\n", .{event_json});
    
    // Parse the values
    var pubkey: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&pubkey, "c8ae68a084ba5eafcf247013928b3758c1d9ceab49987f333cc34b93c1ad0caa");
    
    var event_id: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&event_id, "69f9901ef54b4ca3552053dcd0d6c46d664ebcb1dc3db762e25fbea9146b68ac");
    
    var signature: [64]u8 = undefined;
    _ = try std.fmt.hexToBytes(&signature, "32373101ada75693751dab7eecca4d0bce0d61254ad1aee77245dc91e03f0d2e7044f682b3f7e31aa6efea1cf747564f47e145b013a6fc54a5ae172978202a4a");
    
    // Rebuild the serialized event to verify the hash
    const pubkey_hex = "c8ae68a084ba5eafcf247013928b3758c1d9ceab49987f333cc34b93c1ad0caa";
    const serialized = try nostr.serializeEvent(
        pubkey_hex,
        1756349487,
        1,
        &[_][]const []const u8{&[_][]const u8{"g", "9q"}},
        "[11111]: what up tusk",
        allocator
    );
    defer allocator.free(serialized);
    
    std.debug.print("Serialized event:\n{s}\n\n", .{serialized});
    
    // Compute what the event ID should be
    const computed_id = nostr.computeEventId(serialized);
    var computed_id_hex: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&computed_id_hex, "{}", .{std.fmt.fmtSliceHexLower(&computed_id)});
    
    std.debug.print("Event ID from message: {s}\n", .{"69f9901ef54b4ca3552053dcd0d6c46d664ebcb1dc3db762e25fbea9146b68ac"});
    std.debug.print("Computed event ID:     {s}\n", .{computed_id_hex});
    std.debug.print("IDs match: {}\n\n", .{std.mem.eql(u8, &computed_id_hex, "69f9901ef54b4ca3552053dcd0d6c46d664ebcb1dc3db762e25fbea9146b68ac")});
    
    // Verify signature
    var ctx = try secp.Secp256k1.init();
    defer ctx.deinit();
    
    const is_valid = try ctx.verifySchnorr(signature, event_id, pubkey);
    
    std.debug.print("Signature verification: {s}\n", .{if (is_valid) "✅ VALID" else "❌ INVALID"});
    
    if (!is_valid) {
        std.debug.print("\nThis explains why other clients can't see your message!\n", .{});
        std.debug.print("The relay accepts it but other clients reject invalid signatures.\n", .{});
    }
}