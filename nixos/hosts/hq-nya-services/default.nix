{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
  ];

  # Exit node for reaching mainland-only services from abroad.
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraSetFlags = [ "--advertise-exit-node" ];

  time.timeZone = "Asia/Shanghai";

  # On the mainland, fetching from GitHub or the binary cache sometimes fails.
  # A failed run changes nothing and the next night retries; the timeout stops
  # a stalled download from blocking later runs.
  systemd.services.nixos-upgrade.serviceConfig.TimeoutStartSec = "3h";

  boot.loader.grub.device = "/dev/sda";

  system.stateVersion = "25.05";
}
