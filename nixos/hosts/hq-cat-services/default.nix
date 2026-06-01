{ config, pkgs, ... }:

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

  features.core.enable = true;
  features.security.sops.enable = true;
  features.server.openssh.enable = true;
  features.virtualisation.docker.enable = true;
  features.services.tailscale.enable = true;
  features.user.suser.enable = true;

  time.timeZone = "America/Toronto";

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
  boot.loader.grub.useOSProber = true;
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];

  networking.firewall.enable = true;
  services.qemuGuest.enable = true;

  # Mounts
  fileSystems."/home" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  # Cron Jobs
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Seafile GC
      "0 5 * * * root ${pkgs.docker}/bin/docker exec $(${pkgs.docker}/bin/docker ps -q --filter \"label=com.docker.compose.project=hq-cat-services-seafile\" --filter \"label=com.docker.compose.service=seafile\") /opt/seafile/seafile-server-latest/seaf-gc.sh"
      # Gitea Renovate
      "15 * * * * root ${pkgs.docker}/bin/docker start $(${pkgs.docker}/bin/docker ps -a -q --filter \"name=^renovate$\")"
    ];
  };

  system.stateVersion = "25.05";
}
