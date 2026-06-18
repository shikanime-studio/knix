{
  lib,
  ...
}:

with lib;

{
  options.knix = {
    enable = mkEnableOption "Knix opinionated RKE2 server";

    clusterCidr = mkOption {
      type = types.nullOr types.str;
      default = "10.244.0.0/16";
      description = "The IPv4 pod CIDR passed to RKE2.";
    };

    clusterCidrIPv6 = mkOption {
      type = types.nullOr types.str;
      default = "fd00::/108";
      description = "The IPv6 pod CIDR passed to RKE2.";
    };

    nodeCidrMaskSize = mkOption {
      type = types.int;
      default = 24;
      description = "The IPv4 node CIDR mask size passed to the controller manager.";
    };

    nodeCidrMaskSizeIPv6 = mkOption {
      type = types.int;
      default = 112;
      description = "The IPv6 node CIDR mask size passed to the controller manager.";
    };

    serviceCidr = mkOption {
      type = types.nullOr types.str;
      default = "10.96.0.0/12,fd01::/108";
      description = "The service CIDR passed to RKE2.";
    };

    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "The WAN interface used for firewall policy.";
    };

    nodeIP = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The node IPs passed to RKE2.";
    };

    serverAddr = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The server address passed to RKE2.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "The token file passed to RKE2.";
    };
  };
}
