# Zigchat - Minimal Nostr Client in Zig

A lightweight terminal-based Nostr client written in Zig. Connect to geohash-based local channels and chat in real-time.

## Features

- 🚀 **Fast & Minimal**: Sub-2MB binary
- 🌍 **Geohash Channels**: Location-based chat rooms (e.g., "9q" for Central California)
- 💬 **Real-time Messaging**: WebSocket connections to Nostr relays
- 🔐 **Cryptographically Secure**: secp256k1 signatures for all messages
- 🖥️ **Cross-platform**: macOS, Linux, Windows support

## Quick Start

### Download Pre-built Binary

1. Download the latest release from [GitHub releases](https://github.com/tudorbotezan/zigchat/releases)
   - Linux: `zigchat-Linux.tar.gz`
   - macOS: `zigchat-macOS.tar.gz`  
   - Windows: `zigchat-Windows.zip`

2. Extract and run:
```bash
# Extract (Linux/macOS)
tar -xzf zigchat-*.tar.gz

# Run
./zigchat chat 9q           # Connect to geohash 9q
./zigchat chat 9q --debug   # With debug mode
```

### Build from Source

```bash
# Build
zig build

# Connect to Central California channel
./connect.sh

# Or specify custom channel and relay
./connect.sh 9q wss://relay.damus.io
```

## Installation

### Prerequisites

- Zig 0.13.0 or later
- libsecp256k1 (with Schnorr support)

### Install secp256k1

**macOS:**
```bash
brew install secp256k1
```

**Linux:**
```bash
sudo apt-get install libsecp256k1-dev  # Debian/Ubuntu
sudo yum install libsecp256k1-devel    # RHEL/Fedora
```

**Windows:**
Download and install from [bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1)

### Build from Source

```bash
git clone https://github.com/tudorbotezan/zigchat.git
cd zigchat
zig build -Doptimize=ReleaseSafe
```

## Usage

```bash
# Connect to Central California channel (default)
./connect.sh

# Connect to a different geohash channel
./connect.sh 9q8              # San Francisco Bay Area
./connect.sh 9q5              # Los Angeles Area
./connect.sh dr5              # New York City

# Connect to a specific relay
./connect.sh 9q wss://nos.lol
```

### Chat Commands

Once connected:
- Type any message and press Enter to send
- `/users` - Show active users in the channel
- `/block <id>` or `/b <id>` - Block a user (by pubkey, #tag, or username#tag)
- `/unblock <id>` - Unblock a user
- `/blocks` - List all blocked users
- `/quit` - Exit the chat

## Geohash Channels

Zigchat uses geohash prefixes for location-based channels:

- `9q` - Central California
- `9q8` - San Francisco Bay Area  
- `9q5` - Los Angeles Area
- `dr5` - New York City
- `u4p` - London
- `wt` - Tokyo

Shorter prefixes cover larger areas. Find your geohash at [geohash.org](http://geohash.org/).

## Cross-Compilation

Build for different platforms:

```bash
# Linux
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe

# Windows  
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe

# macOS
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe

# ARM64 (Raspberry Pi)
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSafe
```

## Project Structure

```
zigchat/
├── src/
│   ├── main.zig                 # CLI entry point
│   ├── interactive_client.zig   # Chat UI and message handling
│   ├── nostr_ws_client.zig     # Nostr protocol over WebSocket
│   ├── websocket_client.zig    # WebSocket implementation
│   ├── websocket_tls.zig       # TLS/WSS support
│   ├── nostr_crypto.zig        # Cryptographic operations
│   └── message_queue.zig       # Message buffering
├── lib/ws/                     # WebSocket library
├── assets/
│   ├── default-relays.txt      # Fallback relay list
│   └── geohash-relays.json     # Regional relay mapping
└── connect.sh                  # Quick connect script
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT - See [LICENSE](LICENSE) file for details

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- Uses [secp256k1](https://github.com/bitcoin-core/secp256k1) for cryptography
- Implements [Nostr protocol](https://github.com/nostr-protocol/nostr)