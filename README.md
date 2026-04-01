# Yggdrasil

Minimal infra monorepo for [`nixos/`](nixos), [`apps/`](apps), and [`komodo/`](komodo).

## Structure

- [`nixos/`](nixos): hosts, modules, and flake config
- [`apps/`](apps): per-host service stacks
- [`komodo/`](komodo): Komodo infra and resources

## Notes

- prefer [`stack.env`](apps) for shared stack variables
- keep secrets under [`komodo/resources/stacks/any.toml`](nixos/secrets)
