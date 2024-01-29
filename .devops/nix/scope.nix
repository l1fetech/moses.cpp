{
  lib,
  newScope,
  mosesVersion ? "0.0.0",
}:

# We're using `makeScope` instead of just writing out an attrset
# because it allows users to apply overlays later using `overrideScope'`.
# Cf. https://noogle.dev/f/lib/makeScope

lib.makeScope newScope (
  self: {
    inherit mosesVersion;
    moses-cpp = self.callPackage ./package.nix { };
  }
)
