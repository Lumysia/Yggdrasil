{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
  ];

  # Exit node for reaching mainland-only services from abroad.
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraSetFlags = [ "--advertise-exit-node" ];

  time.timeZone = "Asia/Shanghai";

  boot.loader.grub.device = "/dev/sda";

  system.stateVersion = "25.05";
}
