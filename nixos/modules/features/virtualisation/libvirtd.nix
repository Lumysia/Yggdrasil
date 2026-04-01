{ lib, config, ... }:

{
  options.features.virtualisation.libvirtd.enable = lib.mkEnableOption "Libvirtd Virtualisation";

  config = lib.mkIf config.features.virtualisation.libvirtd.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
    };
    programs.virt-manager.enable = true;
  };
}