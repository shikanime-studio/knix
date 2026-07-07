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
    services =
      let
        scrapeConfigs = [
          {
            job_name = "kube-etcd";
            scheme = "http";
            metrics_path = "/metrics";
            static_configs = [ { targets = [ "127.0.0.1:2381" ]; } ];
          }
          {
            job_name = "kube-proxy";
            scheme = "http";
            metrics_path = "/metrics";
            static_configs = [ { targets = [ "127.0.0.1:10249" ]; } ];
          }
        ];
      in
      {
        knix.extraConfig = mkIf (cfg.role == "server") {
          # Expose controller manager for prometheus to scrape metrics
          kube-controller-manager-arg = [ "bind-address=0.0.0.0" ];
          # Expose scheduler for prometheus to scrape metrics
          kube-scheduler-arg = [ "bind-address=0.0.0.0" ];
          # Enable RKE2 supervisor metrics
          supervisor-metrics = true;
        };

        prometheus = mkIf (cfg.role == "server") {
          inherit scrapeConfigs;
        };

        vmagent.prometheusConfig = mkIf (cfg.role == "server") {
          scrape_configs = scrapeConfigs;
        };
      };
  };
}
