{ lib, config, ... }:

{
  options.features.virtualisation.docker.enable = lib.mkEnableOption "Docker Engine";

  config = lib.mkIf config.features.virtualisation.docker.enable {
    virtualisation.docker = {
      enable = true;
      daemon.settings = {
        userland-proxy = false;
        no-new-privileges = true;
        fixed-cidr-v6 = "fd00::/80";
        ipv6 = true;
      };
    };
  };
}