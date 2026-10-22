{ config, ... }:

let
  docker = config.virtualisation.docker.package;
in

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/server-vm.nix
    ../../profiles/pve-disks.nix
  ];

  time.timeZone = "America/Toronto";

  # Seafile garbage collection (runs inside the Komodo-managed seafile container).
  systemd.services.seafile-gc = {
    description = "Seafile garbage collection";
    serviceConfig.Type = "oneshot";
    path = [ docker ];
    script = ''
      container=$(docker ps -q \
        --filter label=com.docker.compose.project=hq-cat-services-seafile \
        --filter label=com.docker.compose.service=seafile)
      if [ -z "$container" ]; then
        echo "seafile container not running" >&2
        exit 1
      fi
      docker exec "$container" /opt/seafile/seafile-server-latest/seaf-gc.sh
    '';
  };
  systemd.timers.seafile-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
    };
  };

  system.stateVersion = "25.05";
}
