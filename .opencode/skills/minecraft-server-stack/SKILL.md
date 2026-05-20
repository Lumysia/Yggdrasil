---
name: minecraft-server-stack
description: Use when adding or changing Minecraft server Docker/Compose stacks, modpack server packs, itzg/minecraft-server settings, local startup tests, or cleanup after MC stack testing.
compatibility: opencode
metadata:
  scope: project
  game: minecraft
  workflow: server-stack-testing
---

# Minecraft Server Stack

## Scope

Use this skill for Minecraft server stack work, including Docker Compose, Komodo stack wiring, `itzg/minecraft-server`, server pack deployment, bind mounts, ports, backups, and local startup testing.

Do not use this skill for translation-only work. Use `minecraft-modpack-translator` for quest/config translation and overwrite folders.

## Server Pack Rule

Use the official server pack when one exists.

Do not test a dedicated server by starting the client modpack and excluding client-only mods unless there is no server pack and the user approves that approach.

For `itzg/minecraft-server`, prefer the manual CurseForge server pack flow for official server pack ZIPs:

```text
TYPE=CURSEFORGE
CF_SERVER_MOD=/downloads/<server-pack>.zip
```

Mount the host downloads directory to `/downloads`.

## Local Startup Test

Before adding or changing a Minecraft server stack, run a minimal local server-pack startup test before committing or telling the user it is ready.

For local Docker tests:

1. Create a temporary test compose outside the repo, such as under `~/Downloads` or another approved temp path.
2. Mount the server pack/downloads and any overwrite config folder read-only where possible.
3. Use a clean temporary `/data` directory for each materially different test so old failed installs do not affect results.
4. Start with `docker compose up -d`, not foreground `up`.
5. Wait briefly with a bounded command, then inspect container status and logs in one shot with `docker compose ps` and `docker compose logs --no-color --tail=<n>`.
6. Treat a server that reaches startup completion as a passed minimal startup test; report warnings separately from crashes.
7. If a test needs to wait longer, use bounded waits and repeated status/log checks. Do not leave a foreground compose command blocking indefinitely.

## Cleanup

After local MC tests:

1. Stop and remove test containers and networks with `docker compose down --remove-orphans`.
2. Remove temporary test data created only for the test.
3. Remove Docker images pulled only for that test.
4. Do not remove images, volumes, directories, or files that may be used by unrelated user workloads.

## Stack Layout

Follow the repository app stack conventions. For Minecraft stacks in this repo, keep names and paths consistent with nearby `mc-*` stacks.

Prefer bind mounts under `${GAMES_PATH}` for server data, downloads, backups, and config overwrite folders.
