# Disk layout of the Proxmox guests: scsi0 = boot/root, scsi1 = /data, scsi2 = /home.
let
  disk = n: "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi${toString n}";
  dataMount = n: {
    device = disk n;
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };
in
{
  boot.loader.grub.device = disk 0;
  fileSystems."/data" = dataMount 1;
  fileSystems."/home" = dataMount 2;
}
