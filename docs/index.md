# Project Index

This document provides an overview of the files in the `zig_chat` project, grouped by their functionality.

## Table of Contents

*   [Core Application Logic](#core-application-logic)
*   [Nostr Protocol](#nostr-protocol)
*   [WebSocket and Networking](#websocket-and-networking)
*   [User Interface](#user-interface)
*   [Cryptography](#cryptography)
*   [Storage](#storage)
*   [Build and Configuration](#build-and-configuration)
*   [Scripts and Tooling](#scripts-and-tooling)
*   [Documentation](#documentation)
*   [Dependencies](#dependencies)

## Core Application Logic

*   [`src/main.zig`](../src/main.zig): The main entry point of the application.
*   [`src/interactive_client.zig`](../src/interactive_client.zig): Handles interactive command-line client logic.
*   [`src/simple_nostr.zig`](../src/simple_nostr.zig): A simplified Nostr client implementation.
*   [`src/test_nip01.zig`](../src/test_nip01.zig): Tests for NIP-01 functionality.

## Nostr Protocol

*   [`src/nostr/client.zig`](../src/nostr/client.zig): The core Nostr client implementation.
*   [`src/nostr/event.zig`](../src/nostr/event.zig): Handles Nostr event creation and parsing.
*   [`src/nostr/json.zig`](../src/nostr/json.zig): Utilities for Nostr-related JSON handling.
*   [`src/nostr/nip11.zig`](../src/nostr/nip11.zig): Implementation of NIP-11 for relay information.
*   [`src/nostr/nip42.zig`](../src/nostr/nip42.zig): Implementation of NIP-42 for authentication.
*   [`src/nostr/sign.zig`](../src/nostr/sign.zig): Handles Nostr event signing.
*   [`src/nostr/ws.zig`](../src/nostr/ws.zig): Manages WebSocket communication for the Nostr client.
*   [`src/nostr_client.zig`](../src/nostr_client.zig): Older Nostr client implementation.
*   [`src/nostr_ws_client.zig`](../src/nostr_ws_client.zig): Older Nostr WebSocket client.

## WebSocket and Networking

*   [`lib/ws/websocket.zig`](../lib/ws/websocket.zig): The core WebSocket library.
*   [`lib/ws/src/main.zig`](../lib/ws/src/main.zig): Main file for the WebSocket library.
*   [`lib/ws/src/async.zig`](../lib/ws/src/async.zig): Asynchronous WebSocket functionality.
*   [`lib/ws/src/frame.zig`](../lib/ws/src/frame.zig): WebSocket frame handling.
*   [`lib/ws/src/handshake.zig`](../lib/ws/src/handshake.zig): WebSocket handshake logic.
*   [`lib/ws/src/stream.zig`](../lib/ws/src/stream.zig): WebSocket stream handling.
*   [`src/websocket_client.zig`](../src/websocket_client.zig): A basic WebSocket client.
*   [`src/websocket_http.zig`](../src/websocket_http.zig): WebSocket over HTTP.
*   [`src/websocket_tls.zig`](../src/websocket_tls.zig): TLS-enabled WebSocket.
*   [`src/websocket_tls_client.zig`](../src/websocket_tls_client.zig): A TLS-enabled WebSocket client.
*   [`src/tls_websocket.zig`](../src/tls_websocket.zig): Another TLS WebSocket implementation.
*   [`src/tls_websocket_client.zig`](../src/tls_websocket_client.zig): Another TLS WebSocket client.
*   [`ws_proxy.py`](../ws_proxy.py): A WebSocket proxy in Python.
*   [`test_relay.js`](../test_relay.js): A JavaScript test relay.

## User Interface

*   [`src/ui/tui.zig`](../src/ui/tui.zig): Text-based User Interface (TUI) components.
*   [`src/tui_app.zig`](../src/tui_app.zig): The main TUI application logic.

## Cryptography

*   [`src/nostr_crypto.zig`](../src/nostr_crypto.zig): Cryptographic functions for Nostr.
*   [`src/secp256k1.zig`](../src/secp256k1.zig): secp256k1 elliptic curve cryptography implementation.
*   [`verify_sig.zig`](../verify_sig.zig): A utility to verify signatures.

## Storage

*   [`src/store/config.zig`](../src/store/config.zig): Application configuration management.
*   [`src/store/kv.zig`](../src/store/kv.zig): Key-value storage implementation.

## Build and Configuration

*   [`.gitignore`](../.gitignore): Specifies files to be ignored by Git.
*   [`package.json`](../package.json): Node.js package configuration.
*   [`package-lock.json`](../package-lock.json): Exact versions of Node.js dependencies.
*   [`lib/ws/build.zig.zon`](../lib/ws/build.zig.zon): Build configuration for the WebSocket library.

## Scripts and Tooling

*   [`chat.sh`](../chat.sh): Script to start a chat session.
*   [`connect.sh`](../connect.sh): Script to connect to a relay.
*   [`lib/ws/run_iox_tests.sh`](../lib/ws/run_iox_tests.sh): Script to run iox tests for the WebSocket library.
*   [`lib/ws/run_tests.sh`](../lib/ws/run_tests.sh): Script to run tests for the WebSocket library.

## Documentation

*   [`README.md`](../README.md): The main README file for the project.
*   [`QUICK_START.md`](../QUICK_START.md): A guide for getting started quickly.
*   [`NOSTR_SIGNING.md`](../NOSTR_SIGNING.md): Documentation on Nostr signing.
*   [`websocket_guide.md`](../websocket_guide.md): A guide to the WebSocket implementation.
*   [`websocket_implementation_plan.md`](../websocket_implementation_plan.md): The plan for implementing WebSockets.
*   [`websocket_implementation.md`](../websocket_implementation.md): Details of the WebSocket implementation.
*   [`WEBSOCKET_STATUS.md`](../WEBSOCKET_STATUS.md): The status of the WebSocket implementation.
*   [`lib/ws/readme.md`](../lib/ws/readme.md): README for the WebSocket library.

## Dependencies

*   [`lib/ws`](../lib/ws): The WebSocket library used by the project.
