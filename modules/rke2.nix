{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.knix;

  clusterCidr = filter (cidr: cidr != null) [
    cfg.clusterCidr
    cfg.clusterCidrIPv6
  ];
in
{
  description = "Knix RKE2 deployment";

  config = mkIf cfg.enable {
    boot.kernelModules = [
      "br_netfilter"
      "overlay"
      "tcp_bbr"
    ];
    boot.kernel.sysctl = {
      "fs.file-max" = 2097152;
      "fs.inotify.max_user_instances" = 8192;
      "fs.inotify.max_user_watches" = 524288;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.core.default_qdisc" = "fq";
      "net.core.netdev_max_backlog" = 16384;
      "net.core.rmem_default" = 7340032;
      "net.core.rmem_max" = 16777216;
      "net.core.somaxconn" = 4096;
      "net.core.wmem_default" = 7340032;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.${cfg.interface}.rp_filter" = 0;
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.ip_local_port_range" = "1024 65535";
      "net.ipv4.neigh.default.gc_thresh1" = 1024;
      "net.ipv4.neigh.default.gc_thresh2" = 2048;
      "net.ipv4.neigh.default.gc_thresh3" = 4096;
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fin_timeout" = 15;
      "net.ipv4.tcp_keepalive_time" = 600;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_rmem" = "4096 87380 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      "net.ipv6.conf.${cfg.interface}.accept_ra" = 2;
      "net.ipv6.conf.${cfg.interface}.accept_ra_defrtr" = 0;
      "net.ipv6.conf.${cfg.interface}.accept_ra_mtu" = 1;
      "net.ipv6.conf.${cfg.interface}.accept_ra_pinfo" = 1;
      "net.ipv6.conf.${cfg.interface}.accept_redirects" = 0;
      "net.ipv6.conf.${cfg.interface}.autoconf" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;
      "net.netfilter.nf_conntrack_max" = 262144;
      "vm.max_map_count" = 262144;
    };

    services.rke2 = {
      enable = true;
      inherit (cfg) role;
      cisHardening = true;
      manifests = {
        rke2-canal-config.content = {
          apiVersion = "helm.cattle.io/v1";
          kind = "HelmChartConfig";
          metadata = {
            name = "rke2-canal";
            namespace = "kube-system";
          };
          spec.valuesContent = builtins.toJSON {
            flannel = {
              backend = "wireguard";
              iface = cfg.interface;
            };
            encryption = {
              enabled = true;
              type = "wireguard";
            };
            gatewayAPI = {
              enabled = true;
              gatewayClass.create = true;
            };
            hubble = {
              enabled = true;
              relay.enabled = true;
              ui.enabled = true;
            };
            ipam.mode = "kubernetes";
            k8s = {
              requireIPv4PodCIDR = cfg.clusterCidr != null;
              requireIPv6PodCIDR = cfg.clusterCidrIPv6 != null;
            };
            k8sServiceHost = "localhost";
            k8sServicePort = "6443";
            kubeProxyReplacement = true;
            operator.prometheus.enabled = true;
            prometheus.enabled = true;
          };
        };

        rke2-coredns-config.content = {
          apiVersion = "helm.cattle.io/v1";
          kind = "HelmChartConfig";
          metadata = {
            name = "rke2-coredns";
            namespace = "kube-system";
          };
          spec.valuesContent = builtins.toJSON {
            nodelocal.enabled = true;
          };
        };

        rke2-multus-config.content = {
          apiVersion = "helm.cattle.io/v1";
          kind = "HelmChartConfig";
          metadata = {
            name = "rke2-multus";
            namespace = "kube-system";
          };
          spec.valuesContent = builtins.toJSON {
            manifests.dhcpDaemonSet = true;
          };
        };

        rke2-traefik-config.content = {
          apiVersion = "helm.cattle.io/v1";
          kind = "HelmChartConfig";
          metadata = {
            name = "rke2-traefik";
            namespace = "kube-system";
          };
          spec.valuesContent = builtins.toJSON {
            providers.kubernetesGateway.enabled = true;
          };
        };
      };
      extraFlags = [
        (optionalString (clusterCidr != [ ]) "--cluster-cidr=${concatStringsSep "," clusterCidr}")
        "--cni=multus,canal"
        "--ingress-controller=traefik"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=${toString cfg.nodeCidrMaskSize}"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=${toString cfg.nodeCidrMaskSizeIPv6}"
        (optionalString (cfg.serviceCidr != null) "--service-cidr=${cfg.serviceCidr}")
        "--secrets-encryption"
      ];
      gracefulNodeShutdown.enable = true;
    }
    // optionalAttrs (cfg.nodeIP != null) {
      inherit (cfg) nodeIP;
    }
    // optionalAttrs (cfg.serverAddr != null) {
      inherit (cfg) serverAddr;
    }
    // optionalAttrs (cfg.tokenFile != null) {
      inherit (cfg) tokenFile;
    };

    networking.firewall = {
      extraCommands = ''
        ip6tables -A OUTPUT -o ${cfg.interface} -d ::1/128 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fe80::/10 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fc00::/7 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fd00::/108 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fd01::/108 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d 2000::/3 -j REJECT --reject-with icmp6-addr-unreachable
      '';
      extraStopCommands = ''
        ip6tables -D OUTPUT -o ${cfg.interface} -d ::1/128 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fe80::/10 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fc00::/7 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fd00::/108 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fd01::/108 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d 2000::/3 -j REJECT --reject-with icmp6-addr-unreachable 2>/dev/null || true
      '';
      interfaces.${cfg.interface} = {
        allowedTCPPorts = [
          6443
          9345
          10250
          2379
          2380
          2381
          9099
        ];
        allowedUDPPorts = [
          51820
          51821
        ];
        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          }
        ];
      };
    };
  };
}
