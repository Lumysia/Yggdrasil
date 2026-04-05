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

### Public Services

If a service is exposed through Caddy:

- add Caddy labels in `compose.yaml`
- attach the service to a dedicated shared external network
- add the same network to the host `networking/compose.yaml`
- create that network in the Komodo stack `pre_deploy.command`

### Constraint

- keep naming and layout consistent with nearby stacks
- use Angular-style commit messages
