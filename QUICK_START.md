# Bitchat Quick Start

## Connect to #9q Global Channel

Just run:
```bash
./connect.sh
```

## Connect to Other Channels

```bash
./connect.sh bitcoin
./connect.sh nostr
./connect.sh dev
```

## Use Different Relay

```bash
./connect.sh 9q wss://nos.lol
./connect.sh 9q wss://relay.nostr.band
```

## Popular Nostr Relays

- `wss://relay.damus.io` (default)
- `wss://nos.lol`
- `wss://relay.nostr.band`
- `wss://relay.snort.social`
- `wss://nostr.wine`
- `wss://relay.primal.net`

## Build First Time

```bash
zig build
./connect.sh
```

## Stop

Press `Ctrl-C` to disconnect and exit.