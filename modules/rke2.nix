{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.knix;
  rke2ApiServerPort = 6443;
  rke2SupervisorPort = 9345;
  rke2KubeletPort = 10250;
  rke2EtcdClientPort = 2379;
  rke2EtcdPeerPort = 2380;
  rke2EtcdMetricsPort = 2381;
  longhornMetricsPort = 9099;
  canalWireGuardPort = 51820;
  canalWireGuardControlPort = 51821;
  nodePortRange = {
    from = 30000;
    to = 32767;
  };

  mkAutoDeployChart =
    chart:
    let
      baseChart = removeAttrs chart [ "failurePolicy" ];
    in
    if chart.failurePolicy == null then
      baseChart
    else
      baseChart
      // {
        extraFieldDefinitions = (baseChart.extraFieldDefinitions or { }) // {
          inherit (chart) failurePolicy;
        };
      };
in
{
  config = mkIf cfg.enable {
    # RKE2, Canal, Longhorn, and the Tailscale routing setup all depend on
    # bridge netfilter, overlayfs, and BBR being available on the host.
    boot.kernelModules = [
      "br_netfilter"
      "overlay"
      "tcp_bbr"
    ];

    # These values are chosen to keep cluster networking stable under load.
    # They cover forwarding, bridge netfilter, neighbor table pressure,
    # conntrack capacity, and the TCP buffer/window sizing used by the overlay
    # paths on both IPv4 and IPv6.
    boot.kernel.sysctl = {
      # File descriptor and inode watcher ceilings. Longhorn, Flux, and
      # Kubernetes controllers can fan out across many processes and watched
      # paths, so the defaults are too small for a real cluster.
      "fs.file-max" = 2097152;
      "fs.inotify.max_user_instances" = 8192;
      "fs.inotify.max_user_watches" = 524288;

      # Bridge netfilter is required so kube-proxy and the CNI can see traffic
      # that crosses Linux bridges.
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;

      # TCP queue sizing and congestion control tuned for overlay networking
      # and service traffic under sustained load.
      "net.core.default_qdisc" = "fq";
      "net.core.netdev_max_backlog" = 16384;
      "net.core.rmem_default" = 7340032;
      "net.core.rmem_max" = 16777216;
      "net.core.somaxconn" = 4096;
      "net.core.wmem_default" = 7340032;
      "net.core.wmem_max" = 16777216;

      # Disable reverse-path filtering on the interfaces that participate in
      # routing and overlays, then enable IPv4 forwarding for the cluster.
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.${cfg.interface}.rp_filter" = 0;
      "net.ipv4.ip_forward" = 1;

      # Preserve room for ephemeral ports, neighbor cache growth, and keep TCP
      # sessions stable across noisy networks.
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

      # Mirror the IPv4 forwarding posture on IPv6 and accept Router
      # Advertisements on the cluster-facing interface.
      "net.ipv6.conf.${cfg.interface}.accept_ra" = 2;
      "net.ipv6.conf.${cfg.interface}.accept_ra_defrtr" = 0;
      "net.ipv6.conf.${cfg.interface}.accept_ra_mtu" = 1;
      "net.ipv6.conf.${cfg.interface}.accept_ra_pinfo" = 1;
      "net.ipv6.conf.${cfg.interface}.accept_redirects" = 0;
      "net.ipv6.conf.${cfg.interface}.autoconf" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;

      # Conntrack and mmap ceilings for the number of pods, volumes, and
      # long-running components this cluster layout expects.
      "net.netfilter.nf_conntrack_max" = 262144;
      "vm.max_map_count" = 262144;
    };

    services.rke2 = {
      enable = true;
      inherit (cfg) manifests role;
      cisHardening = true;
      nodeLabel = mapAttrsToList (name: value: "${name}=${value}") cfg.labels;
      autoDeployCharts = mapAttrs (_: mkAutoDeployChart) cfg.charts;
      extraFlags = [
        "--cluster-cidr=${cfg.clusterCidr},${cfg.clusterCidrIPv6}"
        "--cni=multus,canal"
        "--ingress-controller=traefik"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=${toString cfg.nodeCidrMaskSize}"
        "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=${toString cfg.nodeCidrMaskSizeIPv6}"
        "--service-cidr=${cfg.serviceCidr}"
        "--secrets-encryption"
      ]
      ++ optional (cfg.tlsSan != [ ]) "--tls-san=${concatStringsSep "," cfg.tlsSan}";
      gracefulNodeShutdown.enable = true;
    }
    // {
      inherit (cfg) nodeIP serverAddr tokenFile;
    };

    services.knix.manifests = {
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
          providers.kubernetesGateway = {
            enabled = true;
            experimentalChannel = true;
          };
        };
      };
    };

    networking.firewall = {
      # IPv6 egress is constrained to local, link-local, and ULA prefixes that
      # the cluster uses. Global IPv6 traffic is rejected unless explicitly
      # allowed elsewhere.
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
          rke2ApiServerPort
          rke2SupervisorPort
          rke2KubeletPort
          rke2EtcdClientPort
          rke2EtcdPeerPort
          rke2EtcdMetricsPort
          longhornMetricsPort
        ];
        allowedUDPPorts = [
          canalWireGuardPort
          canalWireGuardControlPort
        ];
        allowedTCPPortRanges = [ nodePortRange ];
      };
    };
  };
}
