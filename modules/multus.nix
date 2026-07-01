{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.multus = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Multus CNI meta-plugin.";
    };

    extraConfig = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra config merged into the multus HelmChartConfig valuesContent.";
    };
  };

  config = mkIf cfg.multus.enable {
    services.knix = {
      # Multus must be the first CNI plugin so it can delegate to canal
      extraConfig = mkIf (cfg.role == "server") {
        cni = mkBefore [
          "multus"
        ];
      };

      manifests.rke2-multus-config.content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-multus";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON (
          recursiveUpdate {
            dynamicNetworksController.enabled = true;
            thickPlugin.enabled = true;
          } cfg.multus.extraConfig
        );
      };
    };
  };
}
