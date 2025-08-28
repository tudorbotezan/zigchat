# Nostr Event Signing Implementation Guide

## Problem
We need to properly sign Nostr events to send messages that will be accepted by relays. Currently, our events are being rejected because they have invalid signatures.

## Requirements

### 1. Event Structure (NIP-01)
According to Nostr protocol, each event must have:
- `id`: 32-bytes lowercase hex-encoded sha256 of the serialized event data
- `pubkey`: 32-bytes lowercase hex-encoded public key 
- `created_at`: Unix timestamp in seconds
- `kind`: Event type (1 for text notes, 20000 for geohash)
- `tags`: Array of arrays (e.g., `[["g", "9q"]]` for geohash)
- `content`: The message text
- `sig`: **64-bytes lowercase hex Schnorr signature**

### 2. Serialization for ID and Signing
Events must be serialized as a JSON array (no whitespace):
```json
[0, "<pubkey>", <created_at>, <kind>, <tags>, "<content>"]
```
Then:
1. SHA256 hash this serialization → becomes the event `id`
2. Sign this hash with private key → becomes the event `sig`

### 3. Signature Requirements
- **Algorithm**: Schnorr signatures for secp256k1 curve
- **Format**: 64-byte signature encoded as 128-character lowercase hex
- **Signs**: The SHA256 hash of the serialized event (same as `id`)

## Current Issue
Our implementation generates random signatures that aren't cryptographically valid:
```zig
// Current broken implementation:
var sig_bytes: [64]u8 = undefined;
std.crypto.random.bytes(&sig_bytes);  // WRONG: Random bytes, not a real signature
```

## Solution Options

### Option 1: Use Zabi Library (Pure Zig)
```bash
# Add to build.zig.zon dependencies
.dependencies = .{
    .zabi = .{
        .url = "https://github.com/Zabi/zabi/archive/<commit>.tar.gz",
    },
},
```
Zabi provides:
- Pure Zig Schnorr signer with BIP0340 support
- No external C dependencies
- Actively maintained for latest Zig versions

### Option 2: Wrap libsecp256k1 (C Library)
```zig
// Link to libsecp256k1
const c = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_schnorrsig.h");
});
```
Requires installing libsecp256k1 with Schnorr support enabled.

### Option 3: Implement Minimal Schnorr Signing
Using Zig's std.crypto.ecc.Secp256k1:
```zig
const std = @import("std");
const Secp256k1 = std.crypto.ecc.Secp256k1;

// Generate keypair
var seed: [32]u8 = undefined;
std.crypto.random.bytes(&seed);
const key_pair = try Secp256k1.KeyPair.create(seed);

// Sign message (need to implement Schnorr on top of curve ops)
// This is complex and requires implementing BIP340
```

## Recommended Implementation Steps

1. **Generate proper keypair on first run**:
   ```zig
   // Store in ~/.config/bitchat/keypair.json
   const private_key: [32]u8
   const public_key: [32]u8  
   ```

2. **Implement event signing**:
   ```zig
   fn signEvent(event_hash: [32]u8, private_key: [32]u8) ![64]u8 {
       // Use Schnorr signing with secp256k1
   }
   ```

3. **Update sendMessage function**:
   ```zig
   // Serialize event
   const serialized = formatEventArray(pubkey, timestamp, kind, tags, content);
   
   // Hash to get ID
   var event_hash: [32]u8 = undefined;
   std.crypto.hash.sha2.Sha256.hash(serialized, &event_hash, .{});
   
   // Sign the hash
   const signature = try signEvent(event_hash, private_key);
   
   // Build final event with valid signature
   ```

## Test Vectors
To verify implementation, use these test cases from BIP340:
- Private key: `0000000000000000000000000000000000000000000000000000000000000003`
- Public key: `F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9`
- Message: `0000000000000000000000000000000000000000000000000000000000000000`
- Signature: `E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0`

## Quick Fix (Temporary)
For testing purposes only, some relays accept events without signature validation. Try:
- Test relays: `ws://localhost:7000` (run your own)
- Use existing signed events from other clients as templates
- Some relays in "permissive mode" might accept invalid signatures

## Proper Solution
The correct approach is to use Zabi or wrap libsecp256k1 to get proper Schnorr signature support. This ensures:
- Events are accepted by all Nostr relays
- Cryptographic authenticity of messages
- Compatibility with the broader Nostr ecosystem

## References
- [NIP-01: Basic Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [BIP-340: Schnorr Signatures](https://bips.dev/340/)
- [Zabi Library](https://www.zabi.sh/)
- [libsecp256k1](https://github.com/bitcoin-core/secp256k1)