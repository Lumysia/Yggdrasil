---
name: nixos-host
description: Use when adding, removing, or changing NixOS host definitions under nixos/hosts, nixos/flake.nix nixosConfigurations, hostnames, or related Komodo server names.
compatibility: opencode
metadata:
  scope: project
  workflow: nixos-host
---

# NixOS Host

## Host Definitions

- host definitions live under `nixos/hosts/<hostname>/` and are registered in `nixos/flake.nix`
- when adding a NixOS host, add both the host directory and the matching `nixosConfigurations` entry
- when removing a NixOS host, remove both the `nixosConfigurations` entry and the matching `nixos/hosts/<hostname>/` directory
- keep hostnames consistent across the host directory, `networking.hostName`, Komodo server names, and related app paths unless there is an explicit migration reason

## Constraints

- keep naming and layout consistent with nearby hosts
