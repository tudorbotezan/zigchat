#!/usr/bin/env python3
"""
WebSocket proxy to connect to wss:// endpoints from ws:// clients
Usage: python3 ws_proxy.py [local_port] [remote_wss_url]
Example: python3 ws_proxy.py 8080 wss://relay.damus.io
"""

import asyncio
import sys
import websockets
from websockets import client, server

async def forward_messages(source, destination, name):
    """Forward messages from source to destination"""
    try:
        async for message in source:
            print(f"[{name}] Forwarding: {message[:100]}...")
            await destination.send(message)
    except websockets.ConnectionClosed:
        print(f"[{name}] Connection closed")
    except Exception as e:
        print(f"[{name}] Error: {e}")

async def handle_client(local_ws, path):
    """Handle incoming ws:// client connection"""
    remote_url = sys.argv[2] if len(sys.argv) > 2 else "wss://relay.damus.io"
    print(f"Client connected, proxying to {remote_url}")
    
    try:
        # Connect to remote wss:// server
        async with client.connect(remote_url) as remote_ws:
            print(f"Connected to remote {remote_url}")
            
            # Create tasks to forward messages in both directions
            client_to_server = asyncio.create_task(
                forward_messages(local_ws, remote_ws, "C->S")
            )
            server_to_client = asyncio.create_task(
                forward_messages(remote_ws, local_ws, "S->C")
            )
            
            # Wait for either task to complete
            done, pending = await asyncio.wait(
                [client_to_server, server_to_client],
                return_when=asyncio.FIRST_COMPLETED
            )
            
            # Cancel pending tasks
            for task in pending:
                task.cancel()
                
    except Exception as e:
        print(f"Proxy error: {e}")
    finally:
        print("Client disconnected")

async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"Starting WebSocket proxy on ws://localhost:{port}")
    print(f"This will forward to: {sys.argv[2] if len(sys.argv) > 2 else 'wss://relay.damus.io'}")
    print("Press Ctrl-C to stop\n")
    
    # Start server
    await websockets.serve(handle_client, "localhost", port)
    await asyncio.Future()  # Run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nProxy stopped")