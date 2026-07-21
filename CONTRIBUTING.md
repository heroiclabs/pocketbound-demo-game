# Contributing

## Prerequisites

- [Godot 4.6](https://godotengine.org/download/)
- [Docker](https://docs.docker.com/get-docker/) and Docker Compose

## Running locally

**Start the server** (Nakama 3.37.0 + PostgreSQL 18):

```bash
docker-compose up           # first run or after a clean checkout
docker-compose up --build   # after any change to Go files
```

- Game server: `http://localhost:7350`
- Admin console: `http://localhost:7351` (username: `admin`, password: `password`)

**Start the client:**

Open the project in Godot 4.6 and press **Play**. The main scene is `res://scenes/main.tscn`.

To connect to the local server instead of the live server, toggle `use_local_server` on the root `Main` node in the inspector before pressing Play.

**Check Go code without Docker:**

```bash
go vet ./...
```

The Go module is a Nakama plugin and cannot be run or built standalone — `go vet` is the fastest way to catch errors.

## Project structure

See [README.md](README.md) for a full breakdown of the architecture and file layout.

## Making changes

- **Go server:** changes to any `.go` file require `docker-compose up --build` to take effect.
- **Shared data:** `shared/component_registry.json` is read by both the client (`scripts/component_registry.gd`) and the server (`component_registry.go`). Any tile component changes must update this file.
- **UI:** all UI is built programmatically in GDScript — there are no UI nodes in `.tscn` files.

## Pull requests

1. Keep each PR focused on one concern. Bug fix, feature, or refactor — not all three.
2. If you change any RPC contract (name, payload shape, response shape), update both the Go handler and the GDScript caller in the same PR.
3. Run the integration tests before opening a PR:
   - In Godot, run the scenes under `test/integration/` against a local server.
4. Describe *why* the change is needed in the PR body, not just what changed.
