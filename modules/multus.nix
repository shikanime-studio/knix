{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.multus = {
    enable = mkEnableOption "Multus CNI meta-plugin" // {
      default = true;
    };

    extraConfig = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra config merged into the multus HelmChartConfig valuesContent";
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

      manifests.rke2-multus-config.content = mkIf (cfg.multus.extraConfig != { }) {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-multus";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON cfg.multus.extraConfig;
      };
    };
  };
}
