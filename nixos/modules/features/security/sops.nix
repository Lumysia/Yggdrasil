{ lib, config, ... }:

let
  cfg = config.features.security.sops;
  ageKeyFile = "/var/lib/sops-nix/key.txt";
in
{
  options.features.security.sops = {
    enable = lib.mkEnableOption "minimal sops-nix integration";
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = lib.mkDefault ../../../secrets/common.yaml;
      defaultSopsFormat = lib.mkDefault "yaml";
      age.keyFile = lib.mkDefault ageKeyFile;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/sops-nix 0700 root root - -"
    ];
  };
}
