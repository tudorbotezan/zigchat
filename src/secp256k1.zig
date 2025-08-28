const std = @import("std");
const c = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_schnorrsig.h");
    @cInclude("secp256k1_extrakeys.h");
});

pub const Secp256k1 = struct {
    ctx: *c.secp256k1_context,

    pub fn init() !Secp256k1 {
        const ctx = c.secp256k1_context_create(c.SECP256K1_CONTEXT_SIGN | c.SECP256K1_CONTEXT_VERIFY);
        if (ctx == null) {
            return error.ContextCreationFailed;
        }
        return .{ .ctx = ctx.? };
    }

    pub fn deinit(self: *Secp256k1) void {
        c.secp256k1_context_destroy(self.ctx);
    }

    pub fn generateKeypair(self: *Secp256k1) ![32]u8 {
        var private_key: [32]u8 = undefined;
        var rng = std.crypto.random;
        
        // Generate a valid private key
        while (true) {
            rng.bytes(&private_key);
            if (c.secp256k1_ec_seckey_verify(self.ctx, &private_key) == 1) {
                break;
            }
        }
        
        return private_key;
    }

    pub fn getPublicKey(self: *Secp256k1, private_key: [32]u8) ![32]u8 {
        var keypair: c.secp256k1_keypair = undefined;
        
        if (c.secp256k1_keypair_create(self.ctx, &keypair, &private_key) != 1) {
            return error.KeypairCreationFailed;
        }

        var xonly_pubkey: c.secp256k1_xonly_pubkey = undefined;
        var pk_parity: c_int = undefined;
        
        if (c.secp256k1_keypair_xonly_pub(self.ctx, &xonly_pubkey, &pk_parity, &keypair) != 1) {
            return error.PublicKeyExtractionFailed;
        }

        var public_key: [32]u8 = undefined;
        if (c.secp256k1_xonly_pubkey_serialize(self.ctx, &public_key, &xonly_pubkey) != 1) {
            return error.PublicKeySerializationFailed;
        }

        return public_key;
    }

    pub fn signSchnorr(self: *Secp256k1, msg_hash: [32]u8, private_key: [32]u8) ![64]u8 {
        var keypair: c.secp256k1_keypair = undefined;
        
        if (c.secp256k1_keypair_create(self.ctx, &keypair, &private_key) != 1) {
            return error.KeypairCreationFailed;
        }

        var signature: [64]u8 = undefined;
        
        // Sign with Schnorr (BIP340)
        if (c.secp256k1_schnorrsig_sign32(self.ctx, &signature, &msg_hash, &keypair, null) != 1) {
            return error.SigningFailed;
        }

        return signature;
    }

    pub fn verifySchnorr(self: *Secp256k1, signature: [64]u8, msg_hash: [32]u8, public_key: [32]u8) !bool {
        var xonly_pubkey: c.secp256k1_xonly_pubkey = undefined;
        
        if (c.secp256k1_xonly_pubkey_parse(self.ctx, &xonly_pubkey, &public_key) != 1) {
            return error.PublicKeyParseFailed;
        }

        const result = c.secp256k1_schnorrsig_verify(self.ctx, &signature, &msg_hash, 32, &xonly_pubkey);
        return result == 1;
    }
};