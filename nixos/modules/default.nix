# Every feature module, imported once for all hosts. Hosts only switch features on.
{
  imports = [
    ./features/core.nix
    ./features/desktop/flatpak.nix
    ./features/desktop/gaming.nix
    ./features/desktop/gnome.nix
    ./features/hardware/nvidia.nix
    ./features/security/sops.nix
    ./features/server/openssh.nix
    ./features/services/tailscale.nix
    ./features/virtualisation/docker.nix
    ./features/virtualisation/libvirtd.nix
    ./home/users/ivy.nix
    ./home/users/suser.nix
  ];
}
