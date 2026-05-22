# Repository Conventions

This file is the project guidance index. Load the relevant skill for detailed workflows.

## General Principles

- Address problems that exist in the current system.
- Keep naming and layout consistent with nearby files.
- Use Angular-style commit messages.

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
- Prefer positive skill wording that tells the agent what to do. Rewrite avoid/deny constraints as affirmative scope, selection, preservation, or validation rules where practical.
- Make skills guided when they need user input: if the current environment supports interactive choices, forms, or input boxes, use them to collect missing required information step by step instead of asking for a long free-form bundle. When context strongly implies a likely answer, ask the user to confirm or correct that prediction instead of asking from scratch. Use choices only for closed decisions with a known small set of valid answers; use free-form input for open-ended values. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; re-evaluate that language after each user reply. Translate ordinary readable terms in prompts and options; preserve only exact technical identifiers such as literal file names, paths, commands, env vars, IDs, and protocol names.
- Cross-reference another skill only as routing guidance for a different task type, not as a required dependency for executing the current skill.
