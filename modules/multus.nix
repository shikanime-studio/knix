{ config, lib }:

with lib;

let
  cfg = config.services.knix.multus;
in
{
  options.services.knix.multus = {
    enable = mkEnableOption "Multus CNI meta-plugin";

    extraConfig = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra config merged into the multus HelmChartConfig valuesContent.";
    };
  };

  config = mkIf cfg.enable {
    services.knix = {
      # Multus must be the first CNI plugin so it can delegate to canal
      extraConfig.cni = mkBefore [
        "multus"
      ];

      manifests.rke2-multus-config.content = mkIf (cfg.extraConfig != { }) {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-multus";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON cfg.extraConfig;
      };
    };
  };
}
