{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/features/core.nix
    ../../modules/features/security/sops.nix
    ../../modules/features/server/openssh.nix
    ../../modules/features/virtualisation/docker.nix
    ../../modules/features/services/tailscale.nix
    ../../modules/home/users/suser.nix
  ];

  # Feature Flags
  features.core.enable = true;
  features.security.sops.enable = true;
  features.server.openssh.enable = true;
  features.virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings.no-new-privileges = lib.mkForce false;
  features.services.tailscale.enable = true;
  features.user.suser.enable = true;

  time.timeZone = "America/Toronto";

  # Bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];

  networking.firewall.enable = true;
  services.qemuGuest.enable = true;

  # Mounts
  fileSystems."/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  system.stateVersion = "25.05";
}
