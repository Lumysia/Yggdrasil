# Repository Conventions

This file is the project guidance index. Load the relevant skill for detailed workflows.

## General Principles

- Address problems that exist in the current system.
- Keep naming and layout consistent with nearby files.
- Use Angular-style commit messages.
- Base operational guidance on inspected files, settings, and runtime topology; do not give generic fallback advice when the repository has enough context to reason precisely.
- Do not recommend weakening validation, disabling verification, bypassing authentication, or otherwise reducing safety unless inspected configuration proves it is required; state the exact cause and scope when it is required.
- Mount a disposable container path only when leaving an image-declared `VOLUME` unmapped would create an anonymous volume.

## Tailscale ACLs

- Keep Tailnet ACL templates under `tailscale/`.
- Prefer tag-based grants over fixed Tailscale IPs for reusable forwarding rules.
- Treat ACL files as infrastructure policy: they are not secrets, but they do reveal access intent.

## Skill Index

- For app Docker/Compose stack work, Komodo stack wiring, Caddy exposure, OAuth proxy wiring, or app env/path mapping, load the `app-stack` skill.
- For Minecraft server Docker/Compose stack work, server pack deployment, or MC local startup testing, load the `minecraft-server-stack` skill.
- For NixOS host definitions, `nixos/flake.nix` `nixosConfigurations`, hostnames, or Komodo server names, load the `nixos-host` skill.

## Skill Authoring

- Keep this file as the index for choosing which skill to load; put detailed workflow rules in the relevant skill.
- Keep each skill self-contained: after loading a skill, the agent should have the rules needed to complete that workflow using the loaded skill and its bundled references.
- Keep skills transferable: write workflow rules in terms of observable files, nearby conventions, and explicit checks rather than hidden repo knowledge.
- When modifying a skill, read the whole skill file before deciding it is general enough; use search matches only as supporting evidence.
- Keep skill rules general. Avoid hard-coding a specific natural language, locale, mod, app, host, path, tool, or example unless that identifier is truly part of the workflow contract.
- Keep main `SKILL.md` files lean. Move dense details to one-level bundled reference files when that improves readability, and make the main skill state exactly when to read them.
- Keep the main agent as orchestrator for workflows that can grow large. Direct work by the main agent is appropriate for small tasks; delegate work that may consume substantial context or time to subagents when the environment supports them.
- Prefer positive skill wording that tells the agent what to do. Rewrite avoid/deny constraints as affirmative scope, selection, preservation, or validation rules where practical.
- Make skills guided when they need user input: if the current environment supports interactive choices, forms, or input boxes, use them to collect missing required information step by step instead of asking for a long free-form bundle. When context strongly implies a likely answer, ask the user to confirm or correct that prediction instead of asking from scratch. Use choices only for closed decisions with a known small set of valid answers; use free-form input for open-ended values. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; re-evaluate that language after each user reply. Translate ordinary readable terms in prompts and options; preserve only exact technical identifiers such as literal file names, paths, commands, env vars, IDs, and protocol names.
- Cross-reference another skill only as routing guidance for a different task type, not as a required dependency for executing the current skill.
