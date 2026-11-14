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

  # The Seafile search API (rummage in the seafile stack) listens on loopback; share it on the tailnet only.
  systemd.services.rummage-tailnet = {
    description = "Serve the Seafile search API on the tailnet";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${config.services.tailscale.package}/bin/tailscale serve --bg --tcp=8765 tcp://127.0.0.1:8765";
      ExecStop = "${config.services.tailscale.package}/bin/tailscale serve --tcp=8765 off";
    };
  };

  system.stateVersion = "25.05";
}
