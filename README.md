# Yggdrasil

Yggdrasil is the repository I use to manage NixOS hosts and container workloads. Host configuration, Compose stacks, orchestration resources, and network policy are versioned together so changes to the running environment can be traced back to Git.

This README describes how the repository is organized and operated. It does not maintain a separate service inventory. The contents of `apps/` and `komodo/resources/` are the source of truth for what is deployed.

## Repository layout

| Path | Contents |
|---|---|
| `apps/` | Docker Compose stacks, grouped by target host |
| `komodo/infra/` | Compose definitions used to run the control plane and host agents |
| `komodo/resources/` | Servers, stacks, procedures, actions, and other resources imported by Komodo |
| `nixos/` | The Nix flake, host definitions, shared modules, and encrypted secret declarations |
| `tailscale/` | Tailnet access policy |
| `nixos-rebuild.sh` | Wrapper for NixOS installation and rebuilds |
| `komodo-infra-mgnt.sh` | Wrapper for starting and managing Komodo infrastructure |

## How it works

Each machine has a NixOS configuration under `nixos/hosts/` and a matching entry in `nixos/flake.nix`. Shared behavior belongs in `nixos/modules/`; host directories should contain only the differences needed by that machine.

Container stacks live under `apps/<host>/<stack>/`. Runtime configuration belongs in `compose.yaml`, while non-secret values belong in `stack.env`. Values that must not be committed are stored in Komodo and interpolated when a stack is deployed.

Komodo imports the declarations under `komodo/resources/`. The resource sync is managed and has deletion enabled, so removing a declaration from Git also removes that resource on the next sync. A scheduled procedure runs the sync every six hours, then deploys changed stacks carrying the `deploy` tag. Untagged stacks remain manually managed.

Host-to-host management traffic uses the Tailnet. Public ingress is handled by the gateway stack assigned to each relevant host. NixOS secrets are encrypted with SOPS and age; stack secrets are kept in Komodo variables.

## NixOS hosts

Clone the repository and enter it:

```bash
git clone https://github.com/Lumysia/Yggdrasil.git
cd Yggdrasil
```

Hosts that decrypt SOPS secrets need their age private key at `/var/lib/sops-nix/key.txt` with mode `0600`.

Install a new host whose disk has already been partitioned and mounted at `/mnt`:

```bash
./nixos-rebuild.sh --install <hostname>
```

Rebuild an existing host:

```bash
./nixos-rebuild.sh <hostname>
```

The wrapper also supports updating flake inputs, activating on the next boot, and using a network proxy:

```bash
./nixos-rebuild.sh --update <hostname>
./nixos-rebuild.sh --boot <hostname>
./nixos-rebuild.sh --proxy http://proxy.example:8080 <hostname>
```

If `<hostname>` is omitted, the script uses the current machine's hostname.

## Komodo infrastructure

Use the repository wrapper to manage the control plane or a host agent:

```bash
./komodo-infra-mgnt.sh up <variant> [hostname]
./komodo-infra-mgnt.sh ps <variant> [hostname]
./komodo-infra-mgnt.sh logs <variant> [hostname]
./komodo-infra-mgnt.sh down <variant> [hostname]
```

Run `./komodo-infra-mgnt.sh --help` for the accepted variants, commands, image-mirror option, and Compose argument forwarding. Host-specific environment files are stored under `komodo/infra/<variant>/host-env/`. Runtime data defaults to `${HOME}/komodo-data` and can be moved with `KOMODO_INFRA_DATA_DIR`.

After the control plane is running:

1. Add the variables referenced as `[[VARIABLE]]` in `komodo/resources/`.
2. Run the `Sync-Yggdrasil` resource sync.
3. Review the pending resource changes before executing the initial deployment.

## Validation

Check the Nix flake locally:

```bash
cd nixos
nix flake check
```

Render a Compose stack before deploying it:

```bash
cd apps/<host>/<stack>
docker compose config --quiet
```

CI runs `nix flake check` and a dry-run build for every host whenever NixOS configuration changes. Compose and Komodo changes should still be rendered or parsed locally because they are not covered by that workflow.

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE).
