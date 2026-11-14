# Every feature module, imported once for all hosts. Hosts only switch features on.
{
  imports = [
    ./features/core.nix
    ./features/security/sops.nix
    ./features/server/openssh.nix
    ./features/server/sakina-access.nix
    ./features/services/tailscale.nix
    ./features/virtualisation/docker.nix
    ./home/users/suser.nix
  ];
}
