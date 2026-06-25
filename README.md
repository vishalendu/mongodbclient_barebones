# MongoDB Client

Small standalone macOS MongoDB worksheet client.

## Architecture

- Native macOS UI: Swift + AppKit.
- Query engine: `mongosh`, so worksheets use real MongoDB shell JavaScript.
- Connection storage: name/default database in `UserDefaults`, full URI in macOS Keychain; saved profiles do not auto-connect, disconnect keeps the saved profile, remove deletes it.
- Database tree: read-only database/collection metadata loaded through `mongosh`.
- Worksheets: multiple tabs, each with its own target connection, database, query editor, output, and runner.
- Worksheet storage: save/load normal `.js` files on disk.
- No admin UI: destructive actions are only possible if typed as a query.

This keeps idle memory low: no Electron, no embedded browser, no local web server, and no background database sessions.

## Requirements

- macOS with Xcode command line tools.
- `mongosh` available in `PATH`.

Install `mongosh` with Homebrew:

```sh
brew install mongosh
```

## Build

```sh
make build
```

The app is created at:

```text
build/MongoDBClient.app
```

Run it:

```sh
make run
```

## Query Examples

JSON mode works best when the query returns a cursor or value:

```js
db.users.find({ active: true }).limit(50)
```

Shell mode is for normal JavaScript output:

```js
console.log(await db.stats())
```

## Deliberate Limits

- macOS-only for now.
- Connection profiles are local to the Mac user account.
- Each query launches `mongosh`; keep a persistent shell only if startup time becomes annoying.
