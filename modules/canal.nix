{ config, lib, ... }:

with lib;

let
  cfg = config.services.knix;
in
{
  options.services.knix.canal = {
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

  config = {
    # Ensure WireGuard kernel module is loaded when using wireguard backend
    boot.kernelModules = optional (cfg.canal.backend == "wireguard") "wireguard";

    services.knix = {
      # Canal CNI flag
      extraConfig.cni = mkAfter [ "canal" ];

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
              inherit (cfg) backend;
            };
            # veth MTU depends on backend encapsulation overhead
            # host-gw: 0 overhead → 1500
            # vxlan: -50 bytes → 1450 (safe)
            # wireguard: -80 bytes IPv6 → 1400 (safe)
            veth_mtu =
              if cfg.canal.backend == "host-gw" then
                "1500"
              else if cfg.canal.backend == "vxlan" then
                "1450"
              else
                "1400"; # wireguard
          } cfg.canal.extraConfig
        );
      };
    };

    networking.firewall.allowedUDPPorts =
      let
        wireGuardPort = 51820;
        wireGuardControlPort = 51821;
      in
      [
        wireGuardPort
        wireGuardControlPort
      ];
  };
}
