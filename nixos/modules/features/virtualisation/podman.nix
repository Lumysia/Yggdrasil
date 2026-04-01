
{ lib, config, ... }:

{
  options.features.virtualisation.podman.enable = lib.mkEnableOption "Podman";

  config = lib.mkIf config.features.virtualisation.podman.enable {
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };
  };
}