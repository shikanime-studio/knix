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
  options.services.knix.addons.traefik = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable the Traefik addon.";
        };

        extraConfig = mkOption {
          type = types.attrsOf types.raw;
          default = { };
          description = "Additional Traefik Helm chart values merged into rke2-traefik.";
        };
      };
    };
    default = { };
    description = "Traefik addon settings.";
  };

  config = mkIf cfg.addons.traefik.enable {
    services.knix = {
      extraConfig.ingress-controller = mkIf (cfg.role == "server") [ "traefik" ];

      manifests.rke2-traefik-config.content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-traefik";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON (
          recursiveUpdate {
            gateway.enabled = false;
            ingressClass.enabled = true;
            ports = {
              web = {
                port = 80;
                expose.default = true;
                exposedPort = 80;
                protocol = "TCP";
              };
              websecure = {
                port = 443;
                expose.default = true;
                exposedPort = 443;
                protocol = "TCP";
                tls.enabled = true;
              };
            };
            providers = {
              kubernetesIngress.enabled = true;
              kubernetesGateway = {
                enabled = true;
                experimentalChannel = true;
              };
            };
          } cfg.addons.traefik.extraConfig
        );
      };
    };
  };
}
