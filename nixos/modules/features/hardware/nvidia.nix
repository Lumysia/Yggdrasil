{ config, lib, ... }:

{
  options.features.hardware.nvidia.enable = lib.mkEnableOption "Nvidia Drivers";

  config = lib.mkIf config.features.hardware.nvidia.enable {
    hardware.graphics.enable = true;
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      open = true;
      modesetting.enable = true;
      powerManagement.enable = true;
      dynamicBoost.enable = true;
    };
  };
}