---
name: nixos-host
description: Use when adding, removing, or changing NixOS host definitions under nixos/hosts, nixos/flake.nix nixosConfigurations, hostnames, or related Komodo server names.
compatibility: opencode
metadata:
  scope: project
  workflow: nixos-host
---

# NixOS Host

## Guided Intake

Use guided intake when the environment supports interactive choices, forms, or input boxes. Ask for one missing required decision at a time instead of asking the user to provide a long free-form bundle. When context strongly implies a likely answer, ask the user to confirm or correct that prediction instead of asking from scratch. Use choices only for closed decisions with a known small set of valid answers; use free-form input for open-ended values. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; re-evaluate that language after each user reply. Translate ordinary readable terms in prompts and options; preserve only exact technical identifiers such as literal file names, paths, commands, env vars, IDs, and protocol names.

If the target hostname, operation type, source host to copy from, or rename/removal intent is unclear, ask the next blocking question before editing.

## Workflow

1. Inspect existing host directories under `nixos/hosts/` and the `nixosConfigurations` entries in `nixos/flake.nix` before editing.
2. For additions, create the host directory and add the matching flake configuration entry.
3. For removals, remove both the host directory and the matching flake configuration entry.
4. For renames or hostname changes, update all observable references that intentionally use the host name.
5. Validate references by searching for the old and new host names before reporting completion.

## Host Definitions

- host definitions live under `nixos/hosts/<hostname>/` and are registered in `nixos/flake.nix`
- when adding a NixOS host, add both the host directory and the matching `nixosConfigurations` entry
- when removing a NixOS host, remove both the `nixosConfigurations` entry and the matching `nixos/hosts/<hostname>/` directory
- keep hostnames consistent across the host directory, `networking.hostName`, Komodo server names, and related app paths; document any explicit migration reason for an intentional mismatch

## Constraints

- keep naming and layout consistent with nearby hosts

## Completion Summary

Report concisely:

- Host directories added, removed, or changed.
- `nixos/flake.nix` `nixosConfigurations` entries added, removed, or changed.
- Hostname references updated or intentionally left unchanged.
- Validation performed and any rebuild/check not run.
