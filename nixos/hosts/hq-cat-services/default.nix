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
  # services.tailscale.authKeyFile = "/home/suser/tailscalekey";
  features.user.suser.enable = true;

  time.timeZone = "America/Toronto";

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];

  networking.firewall.enable = true;
  
  # Mounts
  fileSystems."/data/infra" = {
    device = "infra";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };
  
  fileSystems."/data/aimodels" = {
    device = "aimodels";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/appdata" = {
    device = "appdata";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/backups" = {
    device = "backups";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/blobstore" = {
    device = "blobstore";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/db" = {
    device = "db";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/downloads" = {
    device = "downloads";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/logs" = {
    device = "logs";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data/media" = {
    device = "media";
    fsType = "virtiofs";
    options = [ "defaults" "nofail" "noatime" ];
  };

  fileSystems."/data-new" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  # Cron Jobs
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Seafile GC
      "0 5 * * * root ${pkgs.docker}/bin/docker exec $(${pkgs.docker}/bin/docker ps -q --filter \"name=^seafile$\") /opt/seafile/seafile-server-latest/seaf-gc.sh"
      # Gitea Renovate
      "15 * * * * root ${pkgs.docker}/bin/docker start $(${pkgs.docker}/bin/docker ps -a -q --filter \"name=^renovate$\")"
    ];
  };

  system.stateVersion = "25.05";
}
