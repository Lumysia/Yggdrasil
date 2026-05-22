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

Do not use this skill for translation-only work unless the translation artifacts affect server deployment, startup, mounts, or overwrite-folder wiring.

## Guided Intake

Use guided intake when the environment supports interactive choices, forms, or input boxes. Ask for one missing required decision at a time instead of asking the user to provide a long free-form bundle. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; keep technical identifiers unchanged.

If the target server, modpack/server-pack source, runtime type, data path, port, or testing expectation is unclear, ask the next blocking question before editing.

## Workflow

1. Inspect nearby Minecraft stacks and the files being changed before editing.
2. Identify whether an official server pack exists and how it should be supplied to the runtime.
3. Make the smallest stack, env, bind mount, or config changes needed for the requested server behavior.
4. Run a bounded local startup test when feasible.
5. Clean up temporary test resources without touching unrelated workloads.
6. Report changed files, server pack source, validation performed, cleanup performed, and any untested assumptions.

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

Before adding or changing a Minecraft server stack, run a minimal local server-pack startup test before committing or telling the user it is ready when local Docker testing is feasible. If the test cannot be run because required files, credentials, Docker access, disk space, or network access are unavailable, report the blocker and perform the strongest available static validation instead.

For local Docker tests:

1. Create a temporary test compose outside the repo under an approved temporary path.
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
3. Remove Docker images only when they were pulled solely for the temporary test and are clearly unrelated to user workloads.
4. Do not remove images, volumes, directories, or files that may be used by unrelated user workloads.

## Stack Layout

For Minecraft stacks, keep names and paths consistent with nearby `mc-*` stacks when they exist.

Prefer bind mounts under `${GAMES_PATH}` for server data, downloads, backups, and config overwrite folders.

For Compose and Komodo wiring:

- keep runtime config in `compose.yaml`
- keep shared non-secret values in `stack.env`
- keep secrets out of `stack.env` unless they are for internal-only services not exposed to the public internet
- use `env_file:` for `stack.env`
- avoid Docker named volumes and anonymous volumes for persistent/runtime mounts
- prefer bind mounts to explicit host paths
- use temporary host paths under `/tmp/<name>` for non-durable writable runtime mounts
- register or update the stack in the matching Komodo `*.toml` when needed
- keep only interpolation source values in Komodo stack `environment` blocks
- pass Komodo-injected variables explicitly through service `environment:` only to containers that need them
- do not assume `~` or a home directory; check the actual runtime user/home

## Completion Summary

Report concisely:

- Stack, env, and config files changed.
- Server pack source and runtime install method.
- Local startup test result or why it could not be run.
- Static validation performed when runtime testing was unavailable.
- Temporary resources cleaned up.
- Follow-up deployment or operator action, if any.
