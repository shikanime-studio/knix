{
  lib,
  ...
}:

with lib;

{
  imports = [
    ./knix.nix
    ./flux.nix
    ./longhorn.nix
    ./monitoring.nix
    ./rke2.nix
  ];

  options.knix.role = mkOption {
    type = types.enum [
      "agent"
      "server"
    ];
    default = "server";
    description = "The RKE2 node role.";
  };
}
