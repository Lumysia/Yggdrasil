{ lib, config, ... }:

{
  options.features.server.openssh.enable = lib.mkEnableOption "OpenSSH Server";

  config = lib.mkIf config.features.server.openssh.enable {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };
  };
}