# SQLink / MySQL Client Mobile

[中文](README.zh-CN.md)

SQLink is a SwiftUI MySQL client for iPhone and iPad. The Xcode product name is
`MySQLClientMobile`, while the app display name is `SQLink`.

The project combines a real MySQL connection layer built on `mysql-nio` with a
mock service fallback for UI development. It includes connection management,
database browsing, table data editing, a SQL workbench, query history and
favorites, and CSV/JSON import/export workflows designed for mobile use.

## Features

- Connection profiles with host, port, username, default database, TLS toggle,
  read-only mode, connection testing, and Keychain-backed password storage.
- Adaptive SwiftUI navigation: tab-based iPhone layout and
  `NavigationSplitView`-based iPad layout.
- Database browser for schemas, tables, views, stored procedures, functions,
  triggers, columns, indexes, and `SHOW CREATE` DDL.
- Table data browser with pagination, grid/card presentations, filtering,
  sorting, row details, insert, update, and delete.
- SQL editor with execution, formatting, `EXPLAIN`, query history, favorites,
  result export, and high-risk SQL confirmation.
- CSV/JSON export for table query results and SQL query results.
- CSV import with file selection, preview, field mapping, empty-string-to-NULL
  handling, per-row insert, progress, and success/failure summary.
- Local persistence with SwiftData for connection metadata, query history, and
  favorite SQL snippets.
- Optional app lock through LocalAuthentication using Face ID, Touch ID, or the
  device passcode.
- SQL safety checks for read-only connections, `DROP`, `TRUNCATE`, and
  `UPDATE`/`DELETE` statements without `WHERE`.

## Project Facts

| Item | Value |
| --- | --- |
| Display name | `SQLink` |
| Xcode product | `MySQLClientMobile` |
| Bundle ID | `com.devonchan.MySQLClientMobile.dev` |
| Version | `1.0.0` |
| iOS deployment target | `17.0` |
| Swift version | `5.9` |
| Recommended Xcode | `16+` |
| Primary MySQL dependency | `mysql-nio` `1.9.1` |

## Getting Started

1. Open `MySQLClientMobile.xcodeproj` in Xcode.
2. Let Xcode resolve Swift Package dependencies. If needed, run
   `File > Packages > Resolve Package Versions`.
3. Select an iPhone or iPad simulator, or a physical iOS/iPadOS device.
4. Build and run the `MySQLClientMobile` target.
5. Create a MySQL connection profile, enter the host, port, username, and
   password, then use test connection before connecting.

When connecting to a MySQL server on the local network, iOS may show a local
network permission prompt. The project already includes
`NSLocalNetworkUsageDescription` in `Info.plist`.

## Dependencies

The Xcode project resolves Swift Packages through
`MySQLClientMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Key direct dependencies include:

- `https://github.com/vapor/mysql-nio.git` pinned at `1.9.1`
- `https://github.com/apple/swift-nio.git`
- `https://github.com/apple/swift-nio-ssl.git`
- `https://github.com/apple/swift-log.git`

The app starts with the real MySQL service when `MySQLNIO` can be imported:

```swift
#if canImport(MySQLNIO)
@StateObject private var session = MySQLSessionStore(client: MySQLNIOClientService())
#else
@StateObject private var session = MySQLSessionStore(client: MockMySQLClientService())
#endif
```

## Architecture

- `MySQLClientMobile/App`: app entry point, adaptive root navigation,
  appearance selection, SwiftData model container, and LocalAuthentication lock.
- `MySQLClientMobile/Core`: domain models, SwiftData storage models,
  Keychain service, MySQL service protocol, real `MySQLNIOClientService`, mock
  service, SQL formatting/export/import tools, and SQL safety guard.
- `MySQLClientMobile/Features`: connection management, database browser, SQL
  editor, table data UI, table designer, import/export flow, history, favorites,
  and settings.
- `MySQLClientMobile/DesignSystem`: shared SwiftUI components such as glass
  cards, badges, top toasts, error banners, empty states, and data grids.

## MySQL Capabilities

The real `MySQLNIOClientService` currently supports:

- Connect, disconnect, and test connection with `SELECT VERSION()`.
- `SHOW DATABASES` and database switching through `USE`.
- Reading tables, views, routines, triggers, columns, indexes, and DDL metadata.
- Paginated table data queries with optional filters and sorting.
- Row-level `INSERT`, `UPDATE`, and `DELETE`; updates and deletes prefer primary
  keys and fall back to NULL-safe whole-row matching when no primary key exists.
- Arbitrary SQL execution and `EXPLAIN`.
- Optional TLS configuration per connection profile.

## Import and Export Notes

- Table export writes the currently loaded table result, including the current
  page, filters, and sort order. It is not a full-table bulk export.
- SQL editor export writes the most recent SQL query result. Statements without
  result columns do not provide export output.
- CSV export includes a UTF-8 BOM to improve compatibility with spreadsheet
  tools that open Chinese or other non-ASCII text.
- CSV import is row-by-row and best suited for small batches.
- Import automatically skips auto-increment and binary columns, supports
  default header-to-column matching, and can treat empty strings as `NULL`.

## Safety Notes and Limitations

- SSH tunneling is not implemented yet. Use VPN, private networks, or test
  databases instead of exposing production MySQL directly to the public internet.
- Several write/import paths currently build SQL literals with escaping. Moving
  these paths to parameter binding is a recommended hardening step.
- High-risk SQL confirmation helps reduce accidents, but it is not a substitute
  for least-privilege database users and tested backups.
- A read-only connection profile blocks write, mutation, and DDL statements in
  the SQL workbench and import flow.
- Affected row counts are represented as summary messages in current simple
  query handling rather than a fully parsed MySQL affected-row model.

## Roadmap

- SSH tunnel support.
- Batch or transactional CSV import.
- Stronger field-type validation for imported values.
- Parameterized write queries for insert, update, delete, and import paths.
- More advanced table filtering and sorting interactions.

