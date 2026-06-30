{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.canal = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Canal CNI meta-plugin.";
    };

    backend = mkOption {
      type = types.enum [
        "host-gw"
        "vxlan"
        "wireguard"
      ];
      default = "wireguard";
      description = ''
        Flannel overlay backend.

        host-gw: Direct routing tables. Zero encapsulation overhead. Requires all
        nodes on the same Layer 2 subnet (works for same-LAN clusters).
        Expected: ~2,200 Mbps on 2.5 Gbps NICs, ~940 Mbps on 1 Gbps NICs.

        vxlan: Encapsulated VXLAN tunnels. Works across L3 networks (multi-subnet).
        Moderate CPU overhead. Expected: ~1,500 Mbps on 2.5 Gbps NICs.

        wireguard: Kernel WireGuard encryption. Highest CPU overhead due to
        single-flow ChaCha20-Poly1305. Default. Expected: ~535 Mbps
        on Intel N150 (single-core limited).
      '';
      example = "host-gw";
    };

    extraConfig = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra config merged into the canal HelmChartConfig valuesContent.";
    };
  };

  config = mkIf cfg.canal.enable {
    # Ensure WireGuard kernel module is loaded when using wireguard backend
    boot.kernelModules = optional (cfg.canal.backend == "wireguard") "wireguard";

    services.knix = {
      # Canal CNI flag
      extraConfig.cni = mkIf (cfg.role == "server") (mkAfter [ "canal" ]);

      # Canal HelmChartConfig — uses services.knix.canal options
      manifests.rke2-canal-config.content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChartConfig";
        metadata = {
          name = "rke2-canal";
          namespace = "kube-system";
        };
        spec.valuesContent = builtins.toJSON (
          recursiveUpdate {
            flannel = {
              inherit (cfg.canal) backend;
            };
          } cfg.canal.extraConfig
        );
      };
    };

    networking.firewall.allowedUDPPorts =
      let
        wireGuardPort = 51820;
        wireGuardControlPort = 51821;
      in
      mkIf (cfg.canal.backend == "wireguard") [
        wireGuardPort
        wireGuardControlPort
      ];
  };
}
