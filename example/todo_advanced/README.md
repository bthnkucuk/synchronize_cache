# TODO Advanced

A hands-on laboratory for `offline_first_sync_drift`: two synced kinds, two
devices against one backend, a per-item "where is this saved?" badge, a panel
that answers "when will it sync?", and a screen of edge cases you can trigger
by hand and watch.

## Overview

Offline-first sync is invisible until it goes wrong, and by then it is too
late to explain it. This example makes it visible:

- **Every item says where it is.** A chip on each card reads `Synced`, `Only
  on this device`, `Changes not sent yet`, `Delete not sent yet`, `Waiting to
  retry`, `Stuck` or `Conflict — needs your decision`. Tap it for the queued
  operations, the attempts, the base version and one sentence about when it
  will be sent.
- **Two devices, one backend.** Open the app twice with `?device=A` and
  `?device=B`: two local databases, one server. Watch a change cross.
- **Nothing happens by magic.** The sync panel shows the countdown to the next
  automatic sync, whether writes go out immediately, and four buttons that do
  it by hand.
- **Failures are explained in words.** "No connection to the server", "Your
  sign-in has expired", "The server refused this item (HTTP 422)" — and
  whether that counted against the item's retry budget.
- **Two kinds settle conflicts differently.** Todos ask you; notes merge
  themselves. Same engine, per-kind strategy.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Web App                         │
├─────────────────────────────────────────────────────────────┤
│  UI Layer          │  Screens + ConflictDialog + DiffViewer │
│  Conflict Handler  │  Manual resolution with user choice    │
│  Repository        │  TodoRepository (CRUD + Outbox)        │
│  Database          │  Drift + SyncDatabaseMixin             │
│  Sync Engine       │  SyncEngine (manual strategy)          │
│  Transport         │  RestTransport (HTTP + conflict aware) │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Dart Frog Backend                       │
├─────────────────────────────────────────────────────────────┤
│  Routes            │  /todos, /notes (CRUD + conflicts)     │
│  Change feed       │  /ws (tells apps when to pull)         │
│  Simulation        │  /simulate/* (outages, other devices)  │
│  Storage           │  In-memory with timestamps             │
└─────────────────────────────────────────────────────────────┘
```

Both kinds share one implementation. The sync contract — paging by
`(updated_at, id)`, the `_baseUpdatedAt` version check, idempotency keys and
soft delete — lives in `lib/api/sync_api.dart` and `lib/repositories/
sync_repository.dart`; `/todos` and `/notes` only declare their record type,
their validation and their name. A second kind that quietly disagreed about
paging or conflicts would not demonstrate anything.

## Features

- **Two synced kinds**: `todos` and `notes`, one engine, one outbox
- **Per-item sync state**: a chip on every card, derived from the outbox
- **Sync panel**: pending and stuck counts, last run, automatic sync with a
  live countdown, "send right after every change", and Send now / Get changes
  / Sync now / Full resync / Retry stuck / Discard stuck
- **Live updates**: a WebSocket wake channel so another device's change
  arrives in about a second — and a switch to turn it off and see the
  difference
- **Devices**: `?device=B` opens a second, independent local database
- **Conflict Detection**: server returns 409 when the base version does not
  match
- **Manual resolution for todos**: local / server / field-by-field merge, and
  for a delete that met someone else's edit, "Delete anyway" vs "Keep their
  version"
- **Automatic resolution for notes**: field-preserving merge, with the sync
  log naming which field came from where
- **Global search**: FTS5 over todos and notes, results while you type,
  highlighted, Turkish-insensitive (`isik` finds `ışık`)
- **Sync lab**: nine experiments you arm and drive yourself
- **Automated sync scenarios**: 14 checks that run against the real engine
  and the real backend and report pass or fail
- **Sync Log**: history of sync operations

## Project Structure

```
todo_advanced/
├── frontend/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/device.dart             # ?device=B → its own database
│   │   ├── database/                   # schemaVersion 3, two kinds + search
│   │   ├── models/                     # Todo, Note
│   │   ├── repositories/               # todos, notes, settings
│   │   ├── search/app_search.dart      # FTS5 wiring + Turkish folding
│   │   ├── scenarios/                  # the 14 automated checks
│   │   ├── services/
│   │   │   ├── sync_service.dart       # owns the engine and the panel state
│   │   │   ├── item_sync_state.dart    # the chip on every card
│   │   │   ├── auto_sync.dart          # the countdown, as pure functions
│   │   │   ├── live_updates.dart       # the /ws client
│   │   │   ├── sync_failure.dart       # failures, in words
│   │   │   ├── network_switch.dart     # the lab's airplane mode
│   │   │   ├── conflict_handler.dart   # manual resolution (todos)
│   │   │   └── notes_conflict_policy.dart  # automatic resolution (notes)
│   │   └── ui/
│   │       ├── screens/                # home, todos, notes, search, lab
│   │       └── widgets/                # chip, sheet, panel, dialog
│   └── test/
│
└── backend/
    ├── routes/
    │   ├── todos/              # CRUD with conflict detection
    │   ├── notes/              # Same contract, second kind
    │   ├── ws.dart             # Live change feed
    │   ├── reset.dart          # Clears every kind
    │   └── simulate/           # Outages and "another device" triggers
    │       ├── bare_conflict.dart
    │       ├── complete.dart
    │       ├── delay.dart
    │       ├── edit_note.dart
    │       ├── empty_page.dart
    │       ├── fail_writes.dart
    │       ├── prioritize.dart
    │       └── reminder.dart
    ├── lib/
    │   ├── api/                # SyncApi: the REST contract, once
    │   ├── models/             # SyncRecord, Todo, Note
    │   ├── repositories/       # SyncRepository + one class per kind
    │   ├── services/           # ChangeHub, SimulationService
    │   └── utils/              # serverNow()
    └── test/
```

## Running the Application

### Prerequisites

- Flutter SDK 3.35+
- Dart SDK 3.8+

### Backend

```bash
cd backend

# Install dependencies
dart pub get

# Run the server
dart_frog dev
```

The server starts at `http://localhost:8080`. Data is in memory, so a restart
empties it; `POST /reset` does the same without a restart.

### Frontend

```bash
cd frontend

# Install dependencies
flutter pub get

# Generate code (modular drift output — see build.yaml for why)
dart run build_runner build --delete-conflicting-outputs

# Run on Chrome
flutter run -d chrome
```

### Two devices, one backend

This is the part worth doing first. Build once and serve the output:

```bash
cd frontend
flutter build web --pwa-strategy=none
python3 -m http.server 8091 --directory build/web
```

Then open **two tabs**:

- <http://localhost:8091/?device=A>
- <http://localhost:8091/?device=B>

Each tab is a *device*: `?device=B` opens the local database
`todo_advanced_b`, which shares nothing with A except the backend. Device A
keeps the original database name, so an installation that already has todos
does not lose them. Natively the same switch is
`--dart-define=DEVICE=B`.

What to try:

1. Create a todo on A. Its chip says **Only on this device**.
2. Press **Send now** on A (or wait for the automatic sync). The chip becomes
   **Synced**, and within a second the todo appears on B — the backend's
   `/ws` feed woke it.
3. Turn **Live updates** off on B (sync panel → the badge in the app bar).
   Change the todo on A again: B does not move until its next automatic sync,
   or until you press **Get changes**. That difference is the whole point of
   the wake channel.
4. Delete the todo on A. After B's next pull it is gone there too — the pull
   brought a tombstone, not an empty answer.

The same flow is checked automatically by scenario **D1** on the *Sync lab →
Automated sync scenarios* screen.

### What each item's chip means

| Chip | Meaning |
|------|---------|
| `Synced` | This device and the server hold the same version. |
| `Only on this device` | Created here, never sent. No other device can see it. |
| `Changes not sent yet` | Edited here; the server still has the older version. |
| `Delete not sent yet` | Deleted here; the server still has it. |
| `Waiting to retry` | The last attempt failed for a reason that is not this item's fault (no connection, expired sign-in, server down). **Attempts are not counted**, so it can never become stuck this way. |
| `Stuck` | The server rejected it until the retry budget (5) ran out. Offers **Retry** and **Discard change**. |
| `Conflict — needs your decision` | Changed here and on another device; the dialog is waiting. |

Tap any chip for "What happens next?": the queued operations with their type,
when they were queued, attempts *x* of 5, the base version they were made
against, the changed fields, the last error, and one sentence about when the
change will actually be sent.

### Sync lab

*Sync lab* is the fourth tab. Each card says what to do, what you should see,
and — the part that matters in sync — what must **not** happen.

| # | Experiment | Expected outcome |
|---|------------|------------------|
| 1 | **No connection** (client-side switch) | Items chip `Only on this device` / `Changes not sent yet`, pending grows, reason "No connection to the server". Attempts stay 0, nothing is lost, and the next Send now delivers everything. |
| 2 | **Sign-in expired (401)** | `Waiting to retry`, reason "Your sign-in has expired". Never becomes stuck. |
| 3 | **Server down (503)** | `Waiting to retry`, reason "The server is having trouble (HTTP 503)". Never becomes stuck. |
| 4 | **The server rejects one item (422)** | After 5 attempts only the poisoned todo is `Stuck`; everything else keeps syncing. Retry and Discard change work from its chip. |
| 5 | **Edited on another device** | A todo opens the conflict dialog; a note merges itself and the sync log names which field came from where. |
| 6 | **Deleted on another device** | The item disappears here after the next pull. |
| 7 | **Two quick edits before a sync** | Both accepted, no conflict with yourself. |
| 8 | **Slow server** | The UI stays usable; the request is bounded by the transport timeout. |
| 9 | **Delete here what another device just edited** | Todos ask: "Delete anyway" or "Keep their version". Notes decide by themselves — the edit wins and the note comes back. |

The *Automated sync scenarios* button on the same screen opens the other kind
of check: 14 scenarios that run by themselves against a scratch database and
the real backend, and report pass or fail with the evidence. Use the lab to
*watch* the behaviour, the scenarios to *prove* it.

### Search

The *Search* tab queries todos and notes at once through an FTS5 index in the
same SQLite file. Results update while you type, matched text is highlighted,
and a chip filters by kind. The index is derived: rows that arrive through a
pull from another device become searchable without a restart, and deleted
rows drop out.

Search folds Turkish letters, because SQLite's trigram tokenizer does not:
`isik`, `ışık`, `IŞIK` and `Isik` all find *Işık Raporu*. The same folding
function goes to both `SearchEngine` and `DriftFtsSearchTransport` — they
must agree, and the library asserts it. Queries shorter than three characters
match nothing: trigram has no shorter tokens.

## API Endpoints

`{kind}` is `todos` or `notes`. Both behave identically — see
`docs/backend-transport.md` for the full contract.

### CRUD Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check (the client probes it before a sync run) |
| GET | `/{kind}` | Pull a page, ordered by `(updated_at, id)` |
| GET | `/{kind}/:id` | Get a single record |
| POST | `/{kind}` | Create with a server-chosen id |
| PUT | `/{kind}/:id` | Upsert with the version check — what the client uses |
| DELETE | `/{kind}/:id` | Soft delete (sets `deleted_at`) |
| POST | `/reset` | Clear **every** kind (development only) |
| GET | `/ws` | Live change feed (WebSocket) |

### Records

Field names are snake_case on the wire. Every `updated_at` / `deleted_at` the
server generates comes from `serverNow()` — UTC, ISO-8601 with `Z`, truncated
to **milliseconds** so browsers can echo a version back unchanged.

```jsonc
// todos
{ "id": "…", "title": "Buy milk", "description": null, "completed": false,
  "priority": 3, "due_date": null,
  "updated_at": "2026-09-19T20:59:44.086Z", "deleted_at": null }

// notes
{ "id": "…", "title": "Groceries", "body": "Milk, bread", "pinned": true,
  "updated_at": "2026-09-19T20:59:44.071Z", "deleted_at": null }
```

`title` is required and must be 1–500 characters; anything else is answered
with `400 {"error": "title is required and must be 1-500 characters"}`.

### Pull parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `updatedSince` | — | Only records with `updated_at` **after** this |
| `limit` | `500` | Clamped to 1…1000 |
| `pageToken` | — | The `nextPageToken` of the previous page |
| `includeDeleted` | `true` | Tombstones are returned unless this is `false` |

```http
GET /notes?updatedSince=2026-09-19T00:00:00.000Z&limit=500&includeDeleted=true

200 OK
X-Next-Page-Token: note-1
{"items": [ … ], "nextPageToken": "note-1"}
```

`nextPageToken` (and the `X-Next-Page-Token` header) are absent on the last
page.

### Conflict and idempotency headers

| Header | Purpose |
|--------|---------|
| `X-Idempotency-Key` | Duplicate request prevention (the client sends the `opId`) |
| `X-Force-Update: true` | Skip the version check on `PUT` (after resolution) |
| `X-Force-Delete: true` | Skip the version check on `DELETE` |
| `X-Base-Updated-At` | Expected server version for a `DELETE` |

On `PUT` the expected version travels **in the body** as `_baseUpdatedAt`,
which is what `RestTransport` sends:

```http
PUT /notes/note-1
X-Idempotency-Key: 0a1b…

{"title": "Groceries", "body": "Milk", "pinned": true,
 "_baseUpdatedAt": "2026-09-19T20:59:44.071Z"}
```

A successful write always answers with the saved record, so the client can
re-base the edits still queued for it.

### Conflict Response (409)

```json
{
  "error": "conflict",
  "current": {
    "id": "note-1",
    "title": "Groceries",
    "body": "Milk",
    "pinned": true,
    "updated_at": "2026-09-19T20:59:44.071Z",
    "deleted_at": null
  }
}
```

### Live change feed (`GET /ws`)

A WebSocket that says *that* something changed, never *what*. The app answers
with its normal pull, so the data still travels over the one code path that
knows about paging, tombstones and conflicts. Nothing breaks without it — the
app just waits for its timer instead.

Two frame types, both JSON text, both server → client (the client never sends
anything):

```json
{"type": "hello",   "clients": 2}
{"type": "changed", "kind": "notes", "id": "note-1", "at": "2026-09-19T20:59:44.071Z"}
```

- `hello` arrives once on connect. `clients` counts the connection that just
  opened, so the first tab sees `1` and the second sees `2`.
- `changed` is broadcast after **every** write the server applies — client
  pushes, deletes and the `/simulate/*` endpoints — because the hub is wired
  to the repositories, not to the routes. Writes that changed nothing (a
  rejected conflict, a simulated failure) produce no frame.
- The device that made the write gets the frame too: the server cannot tell
  whose write it was. Debounce on the client and pull; pulling your own
  change is harmless.
- `POST /reset` deliberately stays silent — a frame per cleared record would
  be a storm. Connected apps notice at their next pull.

```bash
# Watch the feed from a terminal
websocat ws://localhost:8080/ws
```

### Simulation Endpoints

All of them are armed for a number of requests and then consumed, so you can
set one up and watch exactly one sync run hit it. They only affect `/todos`
and `/notes` (plus `/health` for `delay`); `/ws` is never delayed.

| Method | Endpoint | Body | Description |
|--------|----------|------|-------------|
| POST | `/simulate/reminder` | `{"id": "…", "text": "…"}` | Another device appended a reminder to a todo |
| POST | `/simulate/complete` | — | A cron job auto-completed every overdue todo |
| POST | `/simulate/prioritize` | `{"id": "…", "priority": 1}` | Another device changed a todo's priority |
| POST | `/simulate/edit_note` | `{"id": "…", "title"?: "…", "body"?: "…"}` | Another device edited a note; only the fields you send change |
| POST | `/simulate/delay` | `{"milliseconds": 6000, "requests": 1}` | A stalled connection |
| POST | `/simulate/fail_writes` | `{"status": 422, "requests": 5, "id"?: "…"}` | Writes fail with that status. With `id`, only that record fails — and only it uses up a slot |
| POST | `/simulate/bare_conflict` | `{"requests": 1}` | A `409` **without** `current`, as a proxy would send |
| POST | `/simulate/empty_page` | `{"pages": 1, "kind"?: "notes"}` | An empty page that still names a next page |

`{"requests": 0}` disarms `fail_writes`.

The `id` of `fail_writes` matches the `{id}` of `/{kind}/{id}`, which is what
the sync client uses for every upsert and delete. A body-only `POST /{kind}`
carries no id in its path and is therefore never blocked by a scoped failure.

## Demo Scenarios

Everything below is a button in the app now (*Sync lab*), but the `curl`
equivalents are useful when you want to drive the backend from a terminal
while watching the app.

### 1. Trigger and resolve a conflict (todos ask you)

1. Create a todo and press **Send now**. Its chip turns `Synced`.
2. Another device changes it:
   ```bash
   curl -X POST http://localhost:8080/simulate/prioritize \
     -H "Content-Type: application/json" \
     -d '{"id":"<todo-id>","priority":1}'
   ```
3. Edit the same todo here and press **Send now**.
4. The conflict dialog shows both versions. Choose **Use Local**, **Use
   Server**, or **Merge** to pick field by field.

### 2. The same thing with a note (notes decide themselves)

```bash
curl -X POST http://localhost:8080/simulate/edit_note \
  -H "Content-Type: application/json" \
  -d '{"id":"<note-id>","body":"Written by another device"}'
```

Change the note's *title* here, then **Send now**. No dialog: the two
versions are merged field by field, and the sync log says which field came
from which device.

### 3. Delete here what another device edited

```bash
curl -X POST http://localhost:8080/simulate/prioritize \
  -H "Content-Type: application/json" \
  -d '{"id":"<todo-id>","priority":1}'
```

Delete the todo here, then **Send now**. For a todo you are asked: **Delete
anyway** or **Keep their version**. A note answers by itself — the edit wins
and the note comes back, because that is the only automatic answer that
destroys nothing.

### 4. One poisoned item

```bash
curl -X POST http://localhost:8080/simulate/fail_writes \
  -H "Content-Type: application/json" \
  -d '{"status":422,"requests":100,"id":"<todo-id>"}'
```

Edit that todo and press **Send now** five times, editing another todo in
between. Only the poisoned one ends up `Stuck`; the other keeps syncing. Its
chip then offers **Retry** and **Discard change**.

### 5. Watch the wake channel

```bash
websocat ws://localhost:8080/ws
```

Every write you make in either app instance prints a `changed` frame here.
That frame is what makes the other tab update within a second.

### 6. View the sync log

The clock icon in the app bar. It records sync runs, pushes, conflicts, which
fields a merge took from where, and every time the server woke this device.

## Conflict Resolution Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Local Change │     │   Server     │     │   Conflict   │
│   (Push)     │────▶│   (409)      │────▶│   Detected   │
└──────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                                 ▼
                                          ┌──────────────┐
                                          │   Dialog     │
                                          │   Shows      │
                                          └──────────────┘
                                                 │
                     ┌───────────────────────────┼───────────────────────────┐
                     ▼                           ▼                           ▼
              ┌──────────────┐           ┌──────────────┐           ┌──────────────┐
              │ Use Local    │           │ Use Server   │           │    Merge     │
              │ AcceptClient │           │ AcceptServer │           │ AcceptMerged │
              └──────────────┘           └──────────────┘           └──────────────┘
                     │                           │                           │
                     ▼                           ▼                           ▼
              ┌──────────────┐           ┌──────────────┐           ┌──────────────┐
              │ Force Push   │           │ Accept Pull  │           │ Force Push   │
              │ X-Force-*    │           │ (No action)  │           │ Merged Data  │
              └──────────────┘           └──────────────┘           └──────────────┘
```

## Running Tests

### Backend Tests

```bash
cd backend
dart test
```

Tests include:
- CRUD operations for both kinds
- Conflict detection (409 responses)
- Force update/delete headers and idempotency keys
- Paging and tombstones
- Simulation endpoints
- The change hub and what it broadcasts

### Frontend Tests

```bash
cd frontend
flutter test
```

Tests include:
- Model serialization
- Repository operations for both kinds, including what each write queues
- The per-item sync state, every state, without a widget
- The automatic-sync countdown
- Settings persistence
- The live-update client, against a fake channel
- The search wiring: index → query → delete, and Turkish folding
- The v1 → v3 and v2 → v3 migrations
- Conflict handler resolution
- Widget tests for the list, the chip, the panel and the conflict dialog
- End-to-end tests that start a real `dart_frog` backend on a free port

Anything that keeps a live drift subscription must be started explicitly
(`SyncService.start()`), never in a constructor: `pumpAndSettle` runs in a
fake-async zone that never completes real database I/O, so a service that
subscribes while being built deadlocks every widget test that touches it.

## Key Implementation Details

### Conflict Handler

```dart
class ConflictHandler extends ChangeNotifier {
  Future<ConflictResolution> resolve(Conflict conflict) async {
    // Convert to domain objects
    final info = ConflictInfo(
      conflict: conflict,
      localTodo: Todo.fromJson(conflict.localData),
      serverTodo: Todo.fromJson(conflict.serverData),
    );

    // Queue for UI display
    _pendingConflicts.add(info);
    notifyListeners();

    // Wait for user decision
    return await _completer.future;
  }

  void resolveWithLocal() {
    _complete(const AcceptClient());
  }

  void resolveWithServer() {
    _complete(const AcceptServer());
  }

  void resolveWithMerged(Todo merged) {
    _complete(AcceptMerged(merged.toJson()));
  }
}
```

### Sync Configuration

One engine, two kinds, two conflict policies:

```dart
_engine = SyncEngine<AppDatabase>(
  db: db,
  transport: _transport,
  tables: [todoSync, noteSync],
  config: SyncConfig(
    // Todos ask the user.
    conflictStrategy: ConflictStrategy.manual,
    conflictResolver: conflictHandler.resolve,
    pushOnEnqueue: _pushOnChange,
  ),
  tableConflictConfigs: {
    // Notes settle themselves.
    'notes': TableConflictConfig(
      strategy: ConflictStrategy.manual,
      resolver: resolveNoteConflict,
    ),
  },
);
```

Notes look like they should use `ConflictStrategy.autoPreserve` — and their
resolver does exactly what `autoPreserve` does, through
`ConflictUtils.preservingMerge`. They do not, because `autoPreserve` always
answers with `AcceptMerged`, and the engine drops `AcceptMerged` for anything
that is not an upsert. A queued **delete** that meets a server-side edit would
never resolve: the operation would sit in the outbox, be retried by every
sync, and never count as stuck (conflicts do not touch the retry budget).
Running the same merge through the manual hook lets a delete be answered with
something the engine acts on. See `lib/services/notes_conflict_policy.dart`.

`SyncConfig` is fixed for the life of an engine, so the "Send right after
every change" switch rebuilds the engine. `SyncService` forwards events
through its own broadcast stream for that reason — a rebuild closes the
engine's stream underneath anybody listening to it.

### Conflict Detection (Server)

Written once in `lib/repositories/sync_repository.dart`, for every kind:

```dart
// PUT /{kind}/:id — the client sent `_baseUpdatedAt` in the body.
if (!forceUpdate && baseUpdatedAt != null) {
  // Equality, not `isAfter`: any other version means the client edited
  // something the server no longer holds, even an older one.
  if (current.updatedAt != baseUpdatedAt) {
    return OperationConflict(current);
  }
}
```

The equality check is why `serverNow()` truncates to milliseconds — a version
the client cannot echo back unchanged would make every web edit a conflict.

## Diff Viewer

The diff viewer highlights conflicting fields:

```
┌─────────────────────────────────────────┐
│            Sync Conflict                │
├─────────────────────────────────────────┤
│  Field      │  Local    │  Server      │
├─────────────────────────────────────────┤
│  title      │  Buy...   │  Buy...      │
│  completed  │  false    │  true   ⚠️   │
│  priority   │  3        │  1      ⚠️   │
└─────────────────────────────────────────┘
```

## Troubleshooting

### Conflict dialog not appearing

- Ensure `ConflictStrategy.manual` is configured
- Check that `conflictResolver` callback is set
- Verify server returns 409 with `current` data

### Force headers not working

- Headers are case-insensitive: `x-force-update` or `X-Force-Update`
- Value must be exactly `true` (string)

### Simulation endpoints returning 404

- Ensure the todo exists and is synced to server
- Check the todo ID is correct

### The two tabs show the same data

Check the URL: both are probably on the same `?device=`. Device A and device
B are only different because they open different local databases.

### A change does not arrive on the other device

- Is **Live updates** on in the sync panel? With it off, the other device only
  sees the change at its next automatic sync or when you press **Get changes**
  — which is the point of experiment 3 in the two-device walkthrough.
- Is the backend running? The panel says "reconnecting…" when `/ws` is gone.

### Search finds nothing

- Queries shorter than three characters never match: FTS5's trigram tokenizer
  has no shorter tokens.
- The *Search* tab shows how many documents are indexed. If it says 0, the
  indexer did not start — it is started once in `main`.

### The app does not start after an upgrade

Schema version 3 adds notes, settings and the search tables to databases that
were created at v2. If `onUpgrade` throws, the database will not open at all.
`test/database/migration_test.dart` builds a real v2 replica and upgrades it;
run it before shipping a schema change.

## Related

- [todo_simple](../todo_simple/) - Simplified flow without conflicts
- [offline_first_sync_drift documentation](../../../packages/offline_first_sync_drift/)
- [Backend transport guide](../../../docs/backend-transport.md)
