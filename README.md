# Mongo Earlgrey

A fast, native macOS-only MongoDB client built with **SwiftUI**, **AppKit**, and a zero-dependency pure-Swift MongoDB wire protocol (`OP_MSG`) driver. Designed as a clean, responsive, non-destructive alternative to heavy Electron/Java MongoDB GUIs.

---

## Key Features

- **Native macOS Experience**: Built natively for macOS 14+ (Sonoma and newer) on Apple Silicon and Intel, defaulting to Dark Mode with standard macOS keyboard shortcuts and menus.
- **Flexible Connections & Atlas Support**:
  - Starts on a clean **Quick Connect** welcome screen with saved connections, metadata pills (`TLS`, `Auth`, `Sample`), and last-used timestamps.
  - Supports both standard `mongodb://` and `mongodb+srv://` (MongoDB Atlas DNS SRV + TXT `authSource`) connection strings, IPv6 bracketed hosts, TLS/SSL (with optional self-signed certificate support), and `directConnection` mode for SSH tunnels.
  - Authenticates with `SCRAM-SHA-256` (RFC 7677 NFKC normalization + `CommonCrypto` PBKDF2) and `SCRAM-SHA-1`, verifying mutual server signatures (`v=`) in constant time.
- **macOS Keychain Credential Storage**:
  - Passwords and URI credentials are stored in your macOS login Keychain (`com.earlgrey.MongoEarlgrey.credentials`) and redacted before writing connection metadata to `~/Library/Application Support/MongoEarlgrey/connections.json` (`0600`).
- **Studio 3T / `mongosh`-Style Query Bar**:
  - Double-click any database collection (or starred ★ **Favorite Collection**) to open a query tab pre-filled with `db.getCollection("<name>").find({})`.
  - Supports `find`, `findOne`, `count`, `countDocuments`, `aggregate`, `.sort()`, `.limit()`, `.skip()`, `.project()`, Extended JSON v2, and BSON constructors (`ObjectId`, `ISODate`, `NumberLong`/`Long`, `NumberInt`/`Int32`, `NumberDecimal`/`Decimal128`, `UUID`, `BinData`, `Timestamp`, `RegExp`, `MinKey`, `MaxKey`).
  - Expandable multi-line query editor with per-collection persisted **Recent Queries** history across sessions.
- **Fast Results Grid & High-Fidelity Types**:
  - Smooth column resizing and double-click column auto-fit, sortable columns, expandable nested object columns, UTC timestamps, exact IEEE 754-2008 `Decimal128` rendering, full float precision, pop-out nested document/array inspection, and **Export JSON**.
- **High-Performance Document Editor**:
  - Opens wide alongside the grid; chunked background syntax highlighting keeps even multi-megabyte JSON documents snappy to open, edit, and scroll.
  - Built-in **Find (`⌘F`)** bar with `Next` / `Previous` (`⌘G` / `⇧⌘G`), match-case (`Aa`) toggle, match counter, and viewport scroll-to-match.
  - **Format** (validates syntax & normalizes formatting), **Revert**, unsaved-change protection (`NSAlert`), and auto-close confirmation on **Save Document (`⌘S`)**.
- **Safe by Design (Non-Destructive)**:
  - No delete buttons or document/collection delete operations anywhere in the UI or driver—focused strictly on fast querying, inspection, inserting, and safe `_id`-targeted updates.
- **Built-in Sample Database**:
  - Includes an **Earlgrey Sandbox** in-memory store (`earlgrey_store`, `analytics`) so anyone on the team can test queries and editing immediately without a live server.

---

## Prerequisites

- **macOS 14.0 (Sonoma)** or later (Apple Silicon or Intel).
- **Xcode** or **Xcode Command Line Tools** (`swiftc`):
  ```zsh
  xcode-select --install
  ```

---

## Quick Start (Clone, Build & Run)

```zsh
git clone https://github.com/jamesp26/Mongo-Earlgrey.git
cd Mongo-Earlgrey
./build_app.sh
open MongoEarlgrey.app
```

To install it permanently in your Applications folder after building:

```zsh
cp -R MongoEarlgrey.app /Applications/
```

### First-Launch Notes for Team Members

1. **Keychain Access Prompt**: When saving a connection with a password or URI credentials for the first time, macOS will ask if `MongoEarlgrey.app` can access your login Keychain. Click **Always Allow** so saved credentials load automatically on future launches.
   - If you accidentally click *Deny* and cannot reconnect later, quit **Mongo Earlgrey**, run `security delete-generic-password -s com.earlgrey.MongoEarlgrey.credentials` in Terminal, reopen the app, re-enter the credentials in **Connection Manager (`⌘K`)**, and click **Always Allow**.
2. **Ad-hoc / Local Build**: Building locally via `./build_app.sh` avoids Gatekeeper quarantine prompts that apply to downloaded unsigned binaries. If sharing compiled `.app` bundles internally across machines, sign and notarize `MongoEarlgrey.app` with your Developer ID certificate first.

---

## Keyboard Shortcuts

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| `⌘K` | Anywhere | Open Connection Manager |
| `⌘N` | Anywhere | Create New Connection |
| `⌘R` | Connected | Refresh Databases & Collections |
| `Return` / `⌘Return` | Query Bar | Run Query (`Shift+Return` inserts newline) |
| `⇧⌘0` | Active Tab | Reset Query to Default `find({})` |
| `⇧⌘N` | Active Tab | New Document |
| `⌘F` | Document Editor | Open & Focus Find Bar |
| `⌘G` / `⇧⌘G` | Find Bar Open | Find Next / Find Previous Match |
| `Return` / `Shift+Return` | Find Input | Jump to Next / Previous Match |
| `Esc` | Find Input | Close Find Bar & Return Focus to Editor |
| `⌘S` | Document Editor | Save Document (and close editor on success) |
| `⌘W` | Window | Close Active Tab (or Window if no tabs open) |

---

## Project Architecture

```text
Sources/MongoEarlgrey/
├── MongoEarlgreyApp.swift            # App entry point, Dark Mode configuration, native menu commands
├── BSON/
│   ├── BSONDecimal128.swift          # Exact IEEE 754-2008 BID Decimal128 codec
│   └── BSONValue.swift               # Ordered BSONDocument, binary BSONCoder, thread-safe dates & Shell formatter
├── Driver/
│   ├── SCRAMAuthenticator.swift      # SCRAM-SHA-256 / SCRAM-SHA-1 + constant-time server verification
│   ├── SRVResolver.swift             # Non-blocking macOS dnssd SRV + TXT resolver
│   ├── MongoWireConnection.swift     # Network.framework OP_MSG wire protocol + TLS + keepalive + timeouts
│   ├── MongoClient.swift             # Cursor draining (getMore/killCursors), query/insert/replace execution
│   └── DemoMongoStore.swift          # In-memory sample MongoDB engine
├── Query/
│   └── ShellQueryParser.swift        # JavaScriptCore parser for mongosh / Studio 3T syntax & Extended JSON v2
├── Models/
│   ├── KeychainStore.swift           # macOS Keychain storage wrapper
│   ├── ConnectionConfig.swift        # URI parser, field sync, redaction, 0600 connection persistence
│   └── WorkspaceViewModel.swift      # Tab state, persisted query history, unsaved-edits guard
└── Views/
    ├── Theme.swift                   # Connection & BSON value color tokens
    ├── NativeTextField.swift         # AppKit NSTextField bridge with reliable focus & shortcuts
    ├── CodeEditorView.swift          # NSTextView syntax-highlighted editor with chunked highlighting & Find
    ├── ConnectionManagerView.swift   # Connection setup & URI/host editor
    ├── SpreadsheetTableView.swift    # High-density results table with resize, sort & nested expansion
    ├── CollectionTabView.swift       # Query toolbar, split view, inspector & pagination bar
    └── MainWindowView.swift          # Quick Connect home, sidebar tree, favorites & tab bar
```
