# Shared base for the headless server VMs.
{
  features.core.enable = true;
  features.security.sops.enable = true;
  features.server.openssh.enable = true;
  features.virtualisation.docker.enable = true;
  features.services.tailscale.enable = true;
  features.user.suser.enable = true;

  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];

  services.qemuGuest.enable = true;
}
