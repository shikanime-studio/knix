# Knix — VictoriaMetrics monitoring stack for RKE2
#
# Deploys the VictoriaMetrics k8s stack via RKE2 auto-deploy charts.
{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.knix.monitoring;
in
{
  options.knix.monitoring = mkOption {
    type = types.submodule {
      options = {
        enable = mkEnableOption "VictoriaMetrics monitoring stack for RKE2";

        version = mkOption {
          type = types.str;
          default = "0.82.0";
          description = "The VictoriaMetrics k8s stack chart version.";
        };
      };
    };
    default = { };
    description = "Monitoring integration for the Knix RKE2 stack.";
  };

  config = mkIf cfg.enable {
    services.rke2.manifests.monitoring-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "monitoring-system";
        labels = {
          "pod-security.kubernetes.io/audit" = "privileged";
          "pod-security.kubernetes.io/audit-version" = "latest";
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/enforce-version" = "latest";
          "pod-security.kubernetes.io/warn" = "privileged";
          "pod-security.kubernetes.io/warn-version" = "latest";
        };
      };
    };

    services.rke2.manifests.monitoring.content = {
      apiVersion = "helm.cattle.io/v1";
      kind = "HelmChart";
      metadata = {
        name = "victoriametrics";
        namespace = "kube-system";
      };
      spec = {
        chart = "victoria-metrics-k8s-stack";
        createNamespace = true;
        failurePolicy = "abort";
        releaseName = "vmks";
        targetNamespace = "monitoring-system";
        inherit (cfg) version;
        repo = "https://victoriametrics.github.io/helm-charts/";
        valuesContent = builtins.toJSON {
          defaultDashboards.enabled = true;
          kubeProxy.enabled = true;
        };
      };
    };
  };
}
