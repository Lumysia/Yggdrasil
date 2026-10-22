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

  # Nightly self-update from main. Only CI-built changes land on main, so a host
  # pulls what the "NixOS Configuration Check" workflow already built. A reboot
  # happens only when the kernel, initrd or kernel modules changed, and only in
  # the window (host-local time); otherwise the new system is switched to live.
  system.autoUpgrade = {
    enable = true;
    flake = "github:Lumysia/Yggdrasil?dir=nixos";
    dates = "04:00";
    randomizedDelaySec = "30min";
    allowReboot = true;
    rebootWindow = {
      lower = "03:30";
      upper = "06:00";
    };
  };
}
