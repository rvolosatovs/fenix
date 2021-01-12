{ lib, stdenv, symlinkJoin, zlib }:

with builtins;

let
  combine = import ./combine.nix symlinkJoin;
  rpath = "${zlib}/lib:$out/lib";
in mapAttrs (_:
  mapAttrs (profile:
    { date, components }:
    let
      toolchain = mapAttrs (component: source:
        stdenv.mkDerivation {
          pname = "${component}-nightly";
          version = source.date or date;
          src = fetchurl { inherit (source) url sha256; };
          installPhase = ''
            patchShebangs install.sh
            CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

            rm $out/lib/rustlib/{components,install.log,manifest-*,rust-installer-version,uninstall.sh} || true

            if [ -d $out/bin ]; then
              for file in $(find $out/bin -type f); do
                if isELF "$file"; then
                  patchelf \
                    --set-interpreter "$(< ${stdenv.cc}/nix-support/dynamic-linker)" \
                    --set-rpath ${rpath} \
                    "$file" || true
                fi
              done
            fi

            if [ -d $out/lib ]; then
              for file in $(find $out/lib -type f); do
                if isELF "$file"; then
                  patchelf --set-rpath ${rpath} "$file" || true
                fi
              done
            fi

            ${lib.optionalString (component == "clippy-preview") ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib:${rpath} \
                $out/bin/clippy-driver
            ''}
          '';
        }) components;
    in toolchain // {
      toolchain =
        combine "rust-nightly-${profile}-${date}" (attrValues toolchain);
      withComponents = componentNames:
        combine "rust-nightly-${profile}-with-components-${date}"
        (lib.attrVals componentNames toolchain);
    } // lib.optionalAttrs (toolchain ? rustc) {
      rustc = combine "rustc-nightly-with-std-${date}"
        (with toolchain; [ rustc rust-std ]);
      rustc-unwrapped = toolchain.rustc;
    })) (fromJSON (readFile ./toolchains.json))