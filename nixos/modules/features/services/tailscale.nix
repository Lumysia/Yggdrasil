{ lib, config, ... }:

let
  cfg = config.features.services.tailscale;
in
{
  options.features.services.tailscale.enable = lib.mkEnableOption "Tailscale Mesh VPN";

  # Auth is done manually after first boot: sudo tailscale up --authkey <key>
  # The key is one-time; Tailscale state persists in /var/lib/tailscale afterwards.
  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;
  };
}