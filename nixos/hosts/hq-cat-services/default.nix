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

  # Cron Jobs
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Seafile GC
      "0 5 * * * root ${docker}/bin/docker exec $(${docker}/bin/docker ps -q --filter \"label=com.docker.compose.project=hq-cat-services-seafile\" --filter \"label=com.docker.compose.service=seafile\") /opt/seafile/seafile-server-latest/seaf-gc.sh"
      # Gitea Renovate
      "15 * * * * root ${docker}/bin/docker start $(${docker}/bin/docker ps -a -q --filter \"name=^renovate$\")"
    ];
  };

  system.stateVersion = "25.05";
}
