{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
  ];

  # Exit node for reaching mainland-only services from abroad.
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraSetFlags = [ "--advertise-exit-node" ];

  time.timeZone = "Asia/Shanghai";

  # On the mainland it can't reliably fetch from GitHub or the binary cache;
  # deploy it from another host with --target-host instead (see README).
  system.autoUpgrade.enable = lib.mkForce false;

  boot.loader.grub.device = "/dev/sda";

  system.stateVersion = "25.05";
}
