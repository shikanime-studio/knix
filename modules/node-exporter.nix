{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.addons.node-exporter = mkOption {
    enable = mkEnableOption "node-exporter addon" // {
      default = true;
    };
  };

  config = mkIf cfg.addons.node-exporter.enable {
    # Enable textfile collector for node_exporter (k8s DaemonSet)
    systemd.tmpfiles.rules = [
      "d /var/lib/node_exporter/textfile_collector 0755 root root -"
    ];
  };
}
