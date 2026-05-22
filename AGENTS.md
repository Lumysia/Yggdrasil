# Repository Conventions

This file is the project guidance index. Load the relevant skill for detailed workflows.

## General Principles

- Do not defend against problems that do not exist in the current system.
- Keep naming and layout consistent with nearby files.
- Use Angular-style commit messages.

## Skill Index

- For app Docker/Compose stack work, Komodo stack wiring, Caddy exposure, OAuth proxy wiring, or app env/path mapping, load the `app-stack` skill.
- For Minecraft server Docker/Compose stack work, server pack deployment, or MC local startup testing, load the `minecraft-server-stack` skill.
- For NixOS host definitions, `nixos/flake.nix` `nixosConfigurations`, hostnames, or Komodo server names, load the `nixos-host` skill.

## Skill Authoring

- Keep this file as the index for choosing which skill to load; do not put detailed workflow rules here.
- Keep each skill self-contained: after loading a skill, the agent should have the rules needed to complete that workflow without loading another skill or relying on this index.
- Keep skills transferable: write workflow rules in terms of observable files, nearby conventions, and explicit checks rather than hidden repo knowledge.
- When modifying a skill, read the whole skill file before deciding it is general enough; do not rely only on search matches.
- Keep skill rules general. Avoid hard-coding a specific natural language, locale, mod, app, host, path, tool, or example unless that identifier is truly part of the workflow contract.
- Make skills guided when they need user input: if the current environment supports interactive choices, forms, or input boxes, use them to collect missing required information step by step instead of asking for a long free-form bundle. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; keep technical identifiers unchanged.
- Cross-reference another skill only as routing guidance for a different task type, not as a required dependency for executing the current skill.
