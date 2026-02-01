# daemon-ipc

Unix domain socket server for local client communication.

## Purpose

Enables CLI tools and the macOS app to communicate with the daemon via JSON-RPC-like protocol over Unix sockets.

## Key Features

- **Unix socket server**: Listens for local connections
- **Request/response**: JSON-based RPC protocol
- **Subscriptions**: Event streaming to connected clients
- **Method routing**: Extensible handler registration
