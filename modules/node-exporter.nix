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
    type = types.submodule {
      options.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable the configuration for node-exporter.";
      };
    };
    default = { };
    description = "node-exporter addon settings.";
  };

  config = mkIf cfg.addons.node-exporter.enable {
    # Enable textfile collector for node_exporter (k8s DaemonSet)
    systemd.tmpfiles.rules = [
      "d /var/lib/node_exporter/textfile_collector 0755 root root -"
    ];
  };
}
