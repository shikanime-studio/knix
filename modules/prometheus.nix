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
  options.services.knix.addons.prometheus = mkOption {
    type = types.submodule {
      options.enable = mkEnableOption "prometheus addon" // {
        default = true;
      };
    };
    default = { };
    description = "prometheus addon settings";
  };

  config = mkIf cfg.addons.prometheus.enable {
    extraConfig = {
      # Expose scheduler for prometheus to scrape metrics
      kube-scheduler-arg = "--bind-address=0.0.0.0";
      # Expose ETCD for prometheus to scrape metrics
      kube-etcd-arg = "--listen-metrics-urls=http://0.0.0.0:2379";
    };

    # Enable textfile collector for node_exporter (k8s DaemonSet)
    systemd.tmpfiles.rules = [
      "d /var/lib/node_exporter/textfile_collector 0755 root root -"
    ];
  };
}
