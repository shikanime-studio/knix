{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.coredns = mkOption {
    type = types.submodule {
      options = {
        enable = mkEnableOption "CoreDNS node caching" // {
          default = true;
        };

        extraConfig = mkOption {
          type = types.attrsOf types.raw;
          default = { };
          description = "Extra config merged into the coredns HelmChartConfig valuesContent";
        };
      };
    };
    default = { };
    description = "CoreDNS settings";
  };

  config = mkIf cfg.coredns.enable {
    services.knix = {
      extraConfig.disable = mkIf (!cfg.coredns.enable) [ "rke2-coredns" ];

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
          } cfg.coredns.extraConfig
        );
      };
    };
  };
}
