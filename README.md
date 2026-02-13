# ProtoPost

A native macOS desktop tool for testing Protobuf APIs. Think of it as a Postman alternative built specifically for Protocol Buffers — send HTTP requests with binary protobuf payloads, decode protobuf responses into readable JSON, and manage everything in organized workspaces.

## Why ProtoPost?

Testing protobuf-based APIs is painful. You can't just paste a JSON body into Postman and hit send — you need to encode your request into binary protobuf, set the right headers, decode the binary response, and map it all back to your proto definitions. ProtoPost handles all of that automatically.

## Features

- **Workspaces** — Organize your proto files, requests, and settings per project
- **Proto file management** — Register `.proto` files as file system references with automatic import resolution across files
- **HTTP requests** — Send requests with JSON or Protobuf body formats, with automatic binary encoding/decoding
- **Request collections** — Save, name, and organize requests into foldable/draggable groups
- **Authorization** — JWT Bearer and Basic Auth support with workspace-level defaults
- **Environments & variables** — Create multiple environments per workspace with custom variables accessible anywhere via `{{variableName}}`
- **Pre/post request scripting** — JavaScript scripting with a custom `pp` API (similar to Postman's scripting)
- **Generate example JSON** — Auto-generate a JSON payload template from any proto message definition
- **Smart JSON editor** — Syntax highlighting, auto-indent, format/prettify, minify, validate, and tree view
- **Dark mode** — Toggle between light and dark themes
- **Import/Export** — Share workspaces as JSON files with your team

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **protoc** (Protocol Buffers compiler) — required for compiling `.proto` files

Install `protoc` via Homebrew:

```bash
brew install protobuf
```

## Installation

### Option A: Download the pre-built app

1. Download `ProtoPost.zip` from the latest release
2. Unzip it
3. Remove the quarantine attribute (required for unsigned apps):
   ```bash
   xattr -cr ProtoPost.app
   ```
4. Double-click `ProtoPost.app` to run, or drag it to `/Applications`

### Option B: Build from source

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ProtoPost.git
   cd ProtoPost/ProtoConverter
   ```

2. Build the app bundle:
   ```bash
   bash build-app.sh
   open ProtoPost.app
   ```

> **Note:** The first build may take a minute as it fetches and compiles the SwiftProtobuf dependency.

## Quick Start

1. **Create a workspace** — Click the `+` button in the sidebar to create a new workspace
2. **Add proto files** — Go to the "Proto Files" tab and add your `.proto` files (these are file system references, not copies)
3. **Create a request** — Switch to the "Requests" tab, click `+` to create a new request
4. **Configure the request:**
   - Set the URL and HTTP method
   - Choose "Protobuf" as the request/response format
   - Select the message type from the dropdown (populated from your registered proto files)
   - Write your JSON body (or click "Generate" to create a template from the proto definition)
5. **Send it** — ProtoPost encodes your JSON into binary protobuf, sends the request, and decodes the binary response back into readable JSON

## Workspace Settings

Each workspace can have default settings that apply to all requests:

- **Base URL** — Pre-fills the URL for new requests (e.g., `https://api.example.com`)
- **Auth Token** — Sets a default `Authorization` header for all requests
- **Basic Auth** — Default username/password for Basic Authentication
- **Environments** — Create multiple environments (e.g., `dev`, `staging`, `prod`) with custom key-value variables

Access variables anywhere in your requests using `{{variableName}}` syntax — in URLs, headers, body, and auth fields. The editor provides autocomplete suggestions when you type `{{`.

## Scripting

ProtoPost supports JavaScript scripting for pre-request and post-response hooks, using a custom `pp` API:

```javascript
// Pre-request: modify the request before sending
pp.request.headers["X-Custom"] = "value";

// Post-response: extract data from the response
let token = pp.response.json().token;
pp.workspace.set("auth_token", token);

// Log for debugging
console.log("Token:", token);
```

Click the **Scripts** button in the request view and then the **Guide** button for the full API reference.

## Project Structure

```
ProtoConverter/
├── Package.swift                    # Swift package manifest (SwiftProtobuf fetched via SPM)
├── build-app.sh                     # App bundle build script
└── Sources/
    ├── App/
    │   └── ProtoConverterApp.swift   # App entry point & state management
    ├── Models/
    │   ├── Workspace.swift           # Workspace, settings, environments
    │   ├── SavedRequest.swift        # Request model with auth & scripts
    │   ├── RequestGroup.swift        # Request grouping
    │   ├── RequestTabState.swift     # UI state for open request tabs
    │   ├── ProtoFile.swift           # Proto file reference model
    │   ├── MessageTypeInfo.swift     # Proto message type descriptor
    │   └── Environment.swift         # Environment variables model
    ├── Services/
    │   ├── ConversionService.swift   # Proto <-> JSON conversion engine
    │   ├── ProtoCompilerService.swift # protoc integration & import resolution
    │   ├── ScriptingService.swift    # JavaScript scripting engine
    │   ├── VariableService.swift     # {{variable}} substitution
    │   └── WorkspaceManager.swift    # Workspace persistence (JSON files)
    └── Views/
        ├── ContentView.swift         # Main app layout
        ├── HttpRequestView.swift     # Request editor & sender
        ├── SmartJsonEditor.swift     # JSON editor with tree view
        ├── MacTextEditor.swift       # Native NSTextView wrapper
        ├── WorkspaceSidebar.swift    # Sidebar navigation
        ├── RequestsCollectionView.swift # Request list & groups
        ├── ProtoFileListView.swift   # Proto file management
        ├── WorkspaceSettingsView.swift # Workspace settings UI
        ├── ScriptingGuideView.swift  # Scripting API reference
        ├── VariableTextField.swift   # Text field with variable autocomplete
        └── Theme.swift               # UI theme & colors
```

## Tech Stack

- **SwiftUI** — Native macOS UI
- **SwiftProtobuf** — Protobuf descriptor parsing
- **protoc** — Proto file compilation
- **JavaScriptCore** — Scripting engine
- **URLSession** — HTTP networking

## Known Limitations

- The binary protobuf encoder/decoder is a custom implementation. Most common field types work well, but exotic features like `oneof`, `map`, or well-known types (`google.protobuf.Any`, `Timestamp`) may not be fully supported.
- The app is unsigned — macOS Gatekeeper will block it on first launch. Use `xattr -cr ProtoPost.app` or right-click → Open to bypass.

## License

MIT
