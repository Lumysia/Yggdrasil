{ lib, config, pkgs, ... }:

let
  script = "/usr/local/sbin/sakina-access";
in
{
  options.features.server.sakinaAccess.enable =
    lib.mkEnableOption "daily self-update of scripts/sakina-access on hosts where it is installed";

  # The script is installed by hand (see its header). /etc/systemd/system is managed here,
  # so the update timer it writes on other distributions is declared instead.
  config = lib.mkIf config.features.server.sakinaAccess.enable {
    systemd.services.sakina-access-update = {
      description = "Update sakina-access from the Yggdrasil repo";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = script;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${script} update";
      };
    };

    systemd.timers.sakina-access-update = {
      description = "Daily sakina-access update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "4h";
        Persistent = true;
      };
    };
  };
}
