# Bitchat TUI - Minimal Nostr Client in Zig

A tiny terminal client for Nostr protocol, targeting sub-2MB static binary that runs on macOS, Linux, and Windows.

## Features

- **Minimal footprint**: Sub-2MB static binary
- **Cross-platform**: Works on macOS, Linux, and Windows  
- **Pure Zig**: Direct control over WebSocket, JSON, and crypto
- **NIP Support**: 
  - NIP-01: Basic protocol flow
  - NIP-11: Relay information document
  - NIP-42: Authentication
  - NIP-17: Direct messages (planned)

## Building

Requirements:
- Zig 0.13.0 or later
- libsecp256k1 (with Schnorr support enabled)

### Building for your platform

```bash
# Build for your current platform (native)
zig build -Doptimize=ReleaseSafe

# Run
./zig-out/bin/bitchat
```

### Cross-compilation

The build system automatically detects the target OS and adjusts library paths accordingly:

```bash
# Build for Linux (from macOS or Windows)
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe

# Build for Windows (from macOS or Linux)
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe

# Build for macOS (from Linux or Windows)
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe

# Build for ARM64 Linux (e.g., Raspberry Pi)
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSafe
```

### Library paths by platform

The build system expects secp256k1 to be installed in these locations:
- **macOS**: `/opt/homebrew` (Homebrew default)
- **Linux**: `/usr/include` and `/usr/lib` (system packages)
- **Windows**: `C:/secp256k1` (manual installation)

If your libraries are in different locations, you'll need to modify the paths in `build.zig`.

## Usage

```bash
# Generate new keypair
bitchat keygen

# Show current identity  
bitchat whoami

# Manage relays
bitchat relay add wss://relay.example.com
bitchat relay ls
bitchat relay rm 0

# Publish a note
bitchat pub "Hello, Nostr!"

# Subscribe to notes
bitchat sub --kinds 1 --limit 50

# Test authentication
bitchat auth test
```

## Configuration

Config is stored at `~/.config/bitchat/config.json`:

```json
{
  "keys": {
    "sk_hex": "...",
    "pk_hex": "..."
  },
  "relays": [
    {
      "url": "wss://relay.example",
      "read": true,
      "write": true
    }
  ],
  "prefs": {
    "timeout_ms": 8000,
    "max_inflight": 2
  }
}
```

## Project Structure

```
bitchat-tui-zig/
├─ build.zig           # Build configuration
├─ build.zig.zon       # Package manifest
├─ src/
│  ├─ main.zig         # CLI entry point
│  ├─ nostr/           # Protocol implementation
│  │  ├─ ws.zig        # WebSocket client
│  │  ├─ json.zig      # JSON serialization
│  │  ├─ event.zig     # Event structures
│  │  ├─ sign.zig      # BIP-340 Schnorr signatures
│  │  ├─ nip11.zig     # Relay metadata
│  │  ├─ nip42.zig     # Authentication
│  │  └─ client.zig    # Relay pool management
│  ├─ store/           # Persistence
│  │  ├─ config.zig    # Configuration management
│  │  └─ kv.zig        # Key-value store
│  └─ ui/
│     └─ tui.zig       # Terminal UI
└─ assets/
   └─ default-relays.txt

```

## Development Status

### Completed (Day 0)
- [x] Project structure setup
- [x] Basic CLI framework
- [x] Module scaffolding

### TODO
- [ ] WebSocket library integration
- [ ] libsecp256k1 bindings
- [ ] Key generation and management
- [ ] Event signing and verification
- [ ] Basic publish/subscribe
- [ ] Relay pool management
- [ ] NIP-11 relay info fetching
- [ ] NIP-42 authentication
- [ ] TUI implementation
- [ ] Binary optimization (<2MB)

## License

MIT