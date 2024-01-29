{
  perSystem =
    { config, lib, ... }:
    {
      apps =
        let
          inherit (config.packages) default;
          binaries = [
            "moses"
            "moses-embedding"
            "moses-server"
            "quantize"
            "train-text-from-scratch"
          ];
          mkApp = name: {
            type = "app";
            program = "${default}/bin/${name}";
          };
        in
        lib.genAttrs binaries mkApp;
    };
}
