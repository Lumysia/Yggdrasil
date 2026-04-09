# Repository Conventions

This file collects reusable project guidance.

## NixOS Conventions

TODO

## App Stack Conventions

### Files

For each app stack:

- keep runtime config in `compose.yaml`
- keep shared non-secret values in `stack.env`
- register the stack in the matching Komodo `*.toml`

### Rules

- prefer putting non-secret app configuration in `stack.env`
- keep secrets out of `stack.env`; exception: passwords for internal-only services (not exposed to the public internet) may be stored in `stack.env`
- in `compose.yaml`, use `env_file:` for `stack.env`
- use `environment:` in `compose.yaml` mainly for:
  - secrets injected from Komodo
  - values built from Komodo-provided variables such as `${COMMON_DOMAIN_A}`
- avoid defining the same variable in both `stack.env` and `compose.yaml` unless there is an intentional override
- in Komodo `*.toml`, keep only interpolation source values in the stack `environment` block

### Environment Mapping Rules

- always inspect the matching Komodo stack `environment` block in `*.toml` before changing app env wiring
- if a variable is injected by Komodo `*.toml`, pass it explicitly through the relevant service `environment:` block in `compose.yaml`
- only add an injected variable to containers that actually need it at runtime
- if a value is derived from an injected variable, build it in `compose.yaml` instead of `stack.env`
- do not keep self-referential mappings in `stack.env` when the same value is already passed in `compose.yaml`
- when `compose.yaml` already passes an injected variable into a container, remove the duplicate mapping from `stack.env`
- keep static, known, non-secret defaults in `stack.env`; if a value is known and non-sensitive, prefer writing the literal value there instead of creating an indirection
- when reviewing a stack, compare against nearby stacks and any provided sample compose only as a reference; do not copy old samples blindly without checking the current `*.toml`

### Public Services

If a service is exposed through Caddy:

- add Caddy labels in `compose.yaml`
- attach the service to a dedicated shared external network
- add the same network to the host `networking/compose.yaml`
- create that network in the Komodo stack `pre_deploy.command`

### Constraint

- keep naming and layout consistent with nearby stacks
- use Angular-style commit messages
