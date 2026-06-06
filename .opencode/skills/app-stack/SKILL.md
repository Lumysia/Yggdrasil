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

Use guided intake when the environment supports interactive choices, forms, or input boxes. Ask for one missing required decision at a time instead of asking the user to provide a long free-form bundle. When context strongly implies a likely answer, ask the user to confirm or correct that prediction instead of asking from scratch. Use choices only for closed decisions with a known small set of valid answers; use free-form input for open-ended values. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; re-evaluate that language after each user reply. Translate ordinary readable terms in prompts and options; preserve only exact technical identifiers such as literal file names, paths, commands, env vars, IDs, and protocol names.

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

## Komodo Tags

- order Komodo resource tags from placement to role to action
- use placement tags first, such as `origin` or `edge`
- use role tags after placement, such as `ingress`, `service`, or `system`
- put action tags last; `deploy` must be the final tag when present
- preserve existing non-action tag order unless the stack's role or placement changes

## Rules

- prefer putting non-secret app configuration in `stack.env`
- keep secrets out of `stack.env`; exception: passwords for internal-only services (not exposed to the public internet) may be stored in `stack.env`
- in `compose.yaml`, use `env_file:` for `stack.env`
- in `compose.yaml`, use bind mounts for persistent/runtime mounts
- always prefer bind mounts to explicit host paths
- if a writable mount has no durable host location requirement, mount it under `/tmp/<name>` instead of using an anonymous volume
- use `environment:` in `compose.yaml` mainly for secrets injected from Komodo and values built from Komodo-provided variables
- define each variable in one place, with duplicate definitions reserved for intentional overrides
- in Komodo `*.toml`, keep only interpolation source values in the stack `environment` block
- for public service domains on the common root, inject `COMMON_DOMAIN_A` and build concrete hostnames in `compose.yaml`
- derive per-service domain names from `COMMON_DOMAIN_A` when possible
- check the actual runtime user/home before using home-relative paths

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
- reuse the path categories above; add a new `*_PATH` name only when existing categories do not fit
- non-durable writable runtime mounts should use explicit `/tmp/<name>` bind mounts rather than `APPDATA_PATH` or Docker volumes

## Environment Mapping

- always inspect the matching Komodo stack `environment` block in `*.toml` before changing app env wiring
- if a variable is injected by Komodo `*.toml`, pass it explicitly through the relevant service `environment:` block in `compose.yaml`
- only add an injected variable to containers that actually need it at runtime
- if a value is derived from an injected variable, build it in `compose.yaml` instead of `stack.env`
- keep injected values passed through `compose.yaml` instead of duplicating self-referential mappings in `stack.env`
- when `compose.yaml` already passes an injected variable into a container, remove the duplicate mapping from `stack.env`
- keep static, known, non-secret defaults in `stack.env`; if a value is known and non-sensitive, prefer writing the literal value there instead of creating an indirection
- when reviewing a stack, compare against nearby stacks and any provided sample compose as references, then verify against the current `*.toml`

## Public Services

If a service is exposed through Caddy:

- add Caddy labels in `compose.yaml`
- attach the service to a dedicated shared external network
- add the same network to the host `gateway/compose.yaml`
- create that network in the Komodo stack `pre_deploy.command`

## Entry Gateway Services

For public services on entry hosts that already have a shared gateway stack:

- keep one public owner for `80` and `443`; do not add direct public `80:...` or `443:...` port mappings to app stacks
- route ordinary HTTP/HTTPS applications through Caddy behind the gateway, and let Caddy terminate TLS and reverse proxy to the app
- expose web apps by adding Caddy labels to the app service and attaching the app to the shared gateway network used by that host
- keep app containers listening on internal container ports or localhost/private host ports unless a protocol specifically requires public exposure
- use gateway TLS passthrough routes only for protocols or applications that must receive the original TLS stream; do not consume SNI passthrough entries for normal web apps that Caddy can terminate
- use gateway TCP routes for non-HTTP TCP services that need public ports; keep those routes in Komodo-injected variables instead of hard-coding per-host forwarding logic in `compose.yaml`
- keep UDP services separate from the TCP/TLS gateway unless the existing gateway stack already has explicit UDP support
- when changing gateway-backed exposure, inspect the app stack, the host gateway stack, and the matching Komodo `*.toml` together so Caddy labels, shared networks, env variables, and route injections stay consistent
- when debugging gateway traffic, distinguish unmatched fallback traffic from intended routes by checking the generated gateway config and backend names in logs before changing app or route configuration

## OAuth-Protected Services

- prefer one local `oauth2-proxy` per host gateway stack
- keep `oauth2-proxy` in the gateway stack, not the app stack; app stacks should only import Caddy snippets
- use `COMMON_OAUTH2_CLIENT_SECRET` and `COMMON_OAUTH2_COOKIE_SECRET` for shared OAuth secrets
- inspect existing gateway stacks for oauth2-proxy networks, Redis, Caddy snippets, and callback routing, then keep new wiring consistent with those observed files

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
