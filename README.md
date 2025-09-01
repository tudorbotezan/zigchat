# Zigchat - Minimal Nostr Client in Zig

A lightweight terminal-based Nostr client written in Zig. Connect to geohash-based local channels and chat in real-time.

## Features

- 🚀 **Fast & Minimal**: Sub-2MB binary
- 🌍 **Geohash Channels**: Location-based chat rooms (e.g., "9q" for Central California)
- 💬 **Real-time Messaging**: WebSocket connections to Nostr relays
- 🔐 **Cryptographically Secure**: secp256k1 signatures for all messages
- 🚫 **Advanced Blocking**: Block users by pubkey, name, or wildcard patterns
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

#### Prerequisites

- Zig 0.14.0 or later
- libsecp256k1 (with Schnorr support)

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
Use vcpkg or download from [bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1)

```bash
git clone https://github.com/tudorbotezan/zigchat.git
cd zigchat
zig build -Doptimize=ReleaseSafe

# Run locally with helper script
./connect.sh 9q
```

## Usage

```bash
# Using pre-built binary
./zigchat chat 9q           # Connect to geohash 9q
./zigchat chat 9q --debug   # With debug mode

# Using helper script (for development)
./connect.sh 9q8            # San Francisco Bay Area
./connect.sh 9q5            # Los Angeles Area
./connect.sh dr5            # New York City
```

### Chat Commands

Once connected:
- Type any message and press Enter to send
- `/users` - Show active users in the channel
- `/quit` - Exit the chat

#### Blocking Features
- `/block <id>` or `/b <id>` - Block by pubkey, #tag, or username#tag
- `/blockname <pattern>` - Block usernames with wildcard support (e.g., `spam*`, `*bot`, `test*123`)
- `/unblock <id>` - Unblock a user by pubkey
- `/unblockname <pattern>` - Unblock a name pattern
- `/blocks` - List all blocked users
- `/blockednames` - List all blocked name patterns

**Wildcard Examples:**
- `spam*` - Blocks any username starting with "spam"
- `*bot` - Blocks any username ending with "bot"
- `test*user` - Blocks usernames starting with "test" and ending with "user"
- `annoying` - Blocks exact username match

## Geohash Channels

Zigchat uses geohash prefixes for location-based channels:

- `9q` - Central California
- `9q8` - San Francisco Bay Area  
- `9q5` - Los Angeles Area
- `dr5` - New York City
- `u4p` - London
- `wt` - Tokyo

Shorter prefixes cover larger areas. Find your geohash at [geohash.org](http://geohash.org/).



## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT - See [LICENSE](LICENSE) file for details

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- Uses [secp256k1](https://github.com/bitcoin-core/secp256k1) for cryptography
- Implements [Nostr protocol](https://github.com/nostr-protocol/nostr)