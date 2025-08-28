# Agent Instructions for Zig Chat Codebase

## Build Commands
- Build: `zig build -Doptimize=ReleaseSafe`
- Run: `zig build run` or `./zig-out/bin/bitchat`
- Test all: `zig build test`
- Test NIP-01: `zig build test-nip01`
- Clean: `rm -rf .zig-cache zig-out`

## Code Style Guidelines
- **Imports**: Use `@import()` for modules, group std imports first, then local modules
- **Memory**: Always use allocators, defer cleanup with `defer _ = gpa.deinit()` or `defer allocator.free()`
- **Error Handling**: Use `try` for propagation, `catch` for handling, return error unions `!T`
- **Naming**: snake_case for functions/variables, PascalCase for types/structs
- **Structs**: Define `init()` and `deinit()` methods, use `.{}` for struct literals
- **WebSocket**: Import from `ws` module at `lib/ws/src/main.zig`
- **Crypto**: Link libsecp256k1 for signatures, located at `/opt/homebrew/{include,lib}`
- **Testing**: Unit tests use `test "name" {}` blocks, run with `zig build test`
- **Formatting**: Use `zig fmt` for consistent formatting
- **Null Safety**: Handle optionals explicitly with `orelse` or `if (optional) |value|`

## Project Structure
- `src/`: Main source code (nostr/, store/, ui/ modules)
- `lib/ws/`: WebSocket library dependency
- Entry point: `src/main.zig` (CLI commands: keygen, whoami, relay, pub, sub)