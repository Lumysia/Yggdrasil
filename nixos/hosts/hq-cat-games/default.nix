{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
    ../../profiles/pve-disks.nix
  ];

  time.timeZone = "America/Toronto";

  system.stateVersion = "25.05";
}
