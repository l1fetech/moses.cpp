{ inputs, ... }:
{
  perSystem =
    {
      config,
      system,
      lib,
      pkgsCuda,
      ...
    }:
    {
      legacyPackages =
        let
          caps.mosesPackagesXavier = "7.2";
          caps.mosesPackagesOrin = "8.7";
          caps.mosesPackagesTX2 = "6.2";
          caps.mosesPackagesNano = "5.3";

          pkgsFor =
            cap:
            import inputs.nixpkgs {
              inherit system;
              config = {
                cudaSupport = true;
                cudaCapabilities = [ cap ];
                cudaEnableForwardCompat = false;
                inherit (pkgsCuda.config) allowUnfreePredicate;
              };
            };
        in
        builtins.mapAttrs (name: cap: (pkgsFor cap).callPackage ./scope.nix { }) caps;

      packages = lib.optionalAttrs (system == "aarch64-linux") {
        jetson-xavier = config.legacyPackages.mosesPackagesXavier.moses-cpp;
        jetson-orin = config.legacyPackages.mosesPackagesOrin.moses-cpp;
        jetson-nano = config.legacyPackages.mosesPackagesNano.moses-cpp;
      };
    };
}
