---
name: app-stack
description: Use when adding or changing app Docker/Compose stacks, stack.env files, Komodo stack TOML, Caddy exposure, OAuth proxy wiring, bind mounts, or app env/path mapping.
compatibility: opencode
metadata:
  scope: project
  workflow: app-stack
---

# App Stack

## Guided Intake

Use guided intake when the environment supports interactive choices, forms, or input boxes. Ask for one missing required decision at a time instead of asking the user to provide a long free-form bundle. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; keep technical identifiers unchanged.

If the target app, stack path, exposure requirement, persistence requirement, or secret source is unclear, ask the next blocking question before editing.

## Workflow

1. Inspect the target stack files and nearby stacks before editing.
2. Identify the matching Komodo `*.toml`, `compose.yaml`, and `stack.env` files that need changes.
3. Make the smallest Compose, env, Caddy, OAuth, bind mount, or path mapping changes needed for the requested app behavior.
4. Validate file syntax and check for duplicate or misplaced environment values.
5. Report changed files, exposed services, persistence paths, injected variables, and any unverified runtime assumptions.

## Files

For each app stack:

- keep runtime config in `compose.yaml`
- keep shared non-secret values in `stack.env`
- register the stack in the matching Komodo `*.toml`

## Rules

- prefer putting non-secret app configuration in `stack.env`
- keep secrets out of `stack.env`; exception: passwords for internal-only services (not exposed to the public internet) may be stored in `stack.env`
- in `compose.yaml`, use `env_file:` for `stack.env`
- in `compose.yaml`, do not use Docker named volumes or anonymous volumes for persistent/runtime mounts
- always prefer bind mounts to explicit host paths
- if a writable mount has no durable host location requirement, mount it under `/tmp/<name>` instead of using an anonymous volume
- use `environment:` in `compose.yaml` mainly for secrets injected from Komodo and values built from Komodo-provided variables
- avoid defining the same variable in both `stack.env` and `compose.yaml` unless there is an intentional override
- in Komodo `*.toml`, keep only interpolation source values in the stack `environment` block
- for public service domains on the common root, inject `COMMON_DOMAIN_A` and build concrete hostnames in `compose.yaml`
- do not inject full per-service domain names from Komodo when they can be derived from `COMMON_DOMAIN_A`
- do not assume `~` or a home directory; check the actual runtime user/home

## Path Variables

- use `APPDATA_PATH=/data/appdata` for application config, app-managed state, and service-specific runtime data that is not a database/blob/media category
- use `DB_PATH=/data/db` for database persistence, including Postgres, MySQL/MariaDB, Redis/Valkey durable data, RabbitMQ state, and similar backing stores
- use `BLOBSTORE_PATH=/data/blobstore` for repository/object/file storage managed by applications
- use `MEDIA_PATH=/data/media` for media libraries, uploads, caches, and generated media assets
- use `DOWNLOADS_PATH=/data/downloads` for downloader working directories and completed downloads
- use `LOGS_PATH=/data/logs` for durable service logs that are intentionally retained outside containers
- use `GAMES_PATH=/data/games` for game server data
- use `AIMODELS_PATH=/data/aimodels` for AI model/cache storage
- for legacy non-HQ VPS stacks, `APPDATA_PATH` may be injected by Komodo as `/root/docker`; keep using the host-specific existing value instead of assuming `/data/appdata`
- do not invent new `*_PATH` names unless existing categories do not fit; prefer reusing the conventions above
- non-durable writable runtime mounts should use explicit `/tmp/<name>` bind mounts rather than `APPDATA_PATH` or Docker volumes

## Environment Mapping

- always inspect the matching Komodo stack `environment` block in `*.toml` before changing app env wiring
- if a variable is injected by Komodo `*.toml`, pass it explicitly through the relevant service `environment:` block in `compose.yaml`
- only add an injected variable to containers that actually need it at runtime
- if a value is derived from an injected variable, build it in `compose.yaml` instead of `stack.env`
- do not keep self-referential mappings in `stack.env` when the same value is already passed in `compose.yaml`
- when `compose.yaml` already passes an injected variable into a container, remove the duplicate mapping from `stack.env`
- keep static, known, non-secret defaults in `stack.env`; if a value is known and non-sensitive, prefer writing the literal value there instead of creating an indirection
- when reviewing a stack, compare against nearby stacks and any provided sample compose only as a reference; do not copy old samples blindly without checking the current `*.toml`

## Public Services

If a service is exposed through Caddy:

- add Caddy labels in `compose.yaml`
- attach the service to a dedicated shared external network
- add the same network to the host `networking/compose.yaml`
- create that network in the Komodo stack `pre_deploy.command`

## OAuth-Protected Services

- prefer one local `oauth2-proxy` per host gateway/networking stack
- keep `oauth2-proxy` in the gateway/networking stack, not the app stack; app stacks should only import Caddy snippets
- use `COMMON_OAUTH2_CLIENT_SECRET` and `COMMON_OAUTH2_COOKIE_SECRET` for shared OAuth secrets
- inspect existing gateway/networking stacks for oauth2-proxy networks, Redis, Caddy snippets, and callback routing, then keep new wiring consistent with those observed files

## Constraints

- keep naming and layout consistent with nearby stacks

## Completion Summary

Report concisely:

- Stack, env, Komodo, and gateway files changed.
- Public domains or Caddy routes added or changed.
- OAuth wiring added or changed.
- Persistent and temporary bind mounts used.
- Secrets or injected variables expected from Komodo.
- Validation performed and any runtime checks not run.
