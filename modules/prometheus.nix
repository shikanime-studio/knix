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
          {
            job_name = "kube-scheduler";
            scheme = "https";
            metrics_path = "/metrics";
            tls_config = {
              ca_file = "/run/vmagent/rke2-server-ca.crt";
              cert_file = "/run/vmagent/rke2-client-admin.crt";
              key_file = "/run/vmagent/rke2-client-admin.key";
            };
            static_configs = [ { targets = [ "127.0.0.1:10259" ]; } ];
          }
          {
            job_name = "kube-controller";
            scheme = "https";
            metrics_path = "/metrics";
            tls_config = {
              ca_file = "/run/vmagent/rke2-server-ca.crt";
              cert_file = "/run/vmagent/rke2-client-admin.crt";
              key_file = "/run/vmagent/rke2-client-admin.key";
            };
            static_configs = [ { targets = [ "127.0.0.1:10257" ]; } ];
          }
          {
            job_name = "rke2-supervisor";
            scheme = "https";
            metrics_path = "/metrics";
            tls_config = {
              ca_file = "/run/vmagent/rke2-server-ca.crt";
              cert_file = "/run/vmagent/rke2-client-admin.crt";
              key_file = "/run/vmagent/rke2-client-admin.key";
            };
            static_configs = [ { targets = [ "127.0.0.1:9345" ]; } ];
          }
        ];
      in
      {
        knix.extraConfig = mkIf (cfg.role == "server") {
          # Expose controller manager for prometheus to scrape metrics
          kube-controller-manager-arg = [
            "authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics"
          ];
          # Expose scheduler for prometheus to scrape metrics
          kube-scheduler-arg = [
            "authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics"
          ];
          supervisor-metrics = true;
        };

        prometheus = mkIf (cfg.role == "server") {
          inherit scrapeConfigs;
        };

        vmagent.prometheusConfig = mkIf (cfg.role == "server") {
          scrape_configs = scrapeConfigs;
        };
      };

    # Required for vmagent to read RKE2 local TLS endpoints without touching
    # /var/lib/rancher/rke2/server/tls directly.
    systemd.tmpfiles.rules = [
      "d /run/vmagent 0750 vmagent vmagent -"
      "L+ /run/vmagent/rke2-server-ca.crt - vmagent vmagent - /var/lib/rancher/rke2/server/tls/server-ca.crt"
      "L+ /run/vmagent/rke2-client-admin.crt - vmagent vmagent - /var/lib/rancher/rke2/server/tls/client-admin.crt"
      "L+ /run/vmagent/rke2-client-admin.key - vmagent vmagent - /var/lib/rancher/rke2/server/tls/client-admin.key"
    ];
  };
}
