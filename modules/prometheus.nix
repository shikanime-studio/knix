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
    services.knix.extraConfig = mkIf (cfg.role == "server") {
      # Expose ETCD for prometheus to scrape metrics
      etcd-arg = "listen-metrics-urls=https://0.0.0.0:2379";
      # Expose scheduler for prometheus to scrape metrics
      kube-scheduler-arg = "bind-address=0.0.0.0";
      # Expose controller for prometheus to scrape metrics
      kube-controller-arg = "bind-address=0.0.0.0";
    };
  };
}
