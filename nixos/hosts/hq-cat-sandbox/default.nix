{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
    ../../profiles/pve-disks.nix
  ];

  virtualisation.docker.daemon.settings.no-new-privileges = lib.mkForce false;

  time.timeZone = "America/Toronto";

  system.stateVersion = "25.05";
}
