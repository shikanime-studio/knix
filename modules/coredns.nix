{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.addons.coredns = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CoreDNS node caching.";
    };

    extraConfig = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra config merged into the coredns HelmChartConfig valuesContent.";
    };
  };

  config = mkIf cfg.addons.coredns.enable {
    services.knix = {
      extraConfig.disable = mkIf (!cfg.addons.coredns.enable) [ "rke2-coredns" ];

      manifests.rke2-coredns-config.content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-coredns";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON (
          recursiveUpdate {
            nodelocal.enabled = true;
          } cfg.addons.coredns.extraConfig
        );
      };
    };
  };
}
