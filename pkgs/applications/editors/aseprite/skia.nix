{ stdenv, lib, fetchFromGitHub, fetchgit, python2, gn, ninja
, fontconfig, expat, icu58, libglvnd, libjpeg, libpng, libwebp, zlib
, mesa, libX11
}:

let
  # skia-deps.nix is generated by: ./skia-make-deps.sh 'angle2|dng_sdk|piex|sfntly'
  depSrcs = import ./skia-deps.nix { inherit fetchgit; };
  gnOld = gn.overrideAttrs (oldAttrs: rec {
    version = "20190403";
    src = fetchgit {
      url = "https://gn.googlesource.com/gn";
      rev = "64b846c96daeb3eaf08e26d8a84d8451c6cb712b";
      sha256 = "1v2kzsshhxn0ck6gd5w16gi2m3higwd9vkyylmsczxfxnw8skgpy";
    };
  });
in
stdenv.mkDerivation {
  name = "skia-aseprite-m71";

  src = fetchFromGitHub {
    owner = "aseprite";
    repo = "skia";
    # latest commit from aseprite-m71 branch
    rev = "89e4ca4352d05adc892f5983b108433f29b2c0c2"; # TODO: Remove the gnOld override
    sha256 = "0n3vrkswvi6rib9zv2pzi18h3j5wm7flmgkgaikcm6q7iw4l2c7x";
  };

  nativeBuildInputs = [ python2 gnOld ninja ];

  buildInputs = [
    fontconfig expat icu58 libglvnd libjpeg libpng libwebp zlib
    mesa libX11
  ];

  preConfigure = with depSrcs; ''
    mkdir -p third_party/externals
    ln -s ${angle2} third_party/externals/angle2
    ln -s ${dng_sdk} third_party/externals/dng_sdk
    ln -s ${piex} third_party/externals/piex
    ln -s ${sfntly} third_party/externals/sfntly
  '';

  configurePhase = ''
    runHook preConfigure
    gn gen out/Release --args="is_debug=false is_official_build=true"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C out/Release skia
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out

    # Glob will match all subdirs.
    shopt -s globstar

    # All these paths are used in some way when building aseprite.
    cp -r --parents -t $out/ \
      include/codec \
      include/config \
      include/core \
      include/effects \
      include/gpu \
      include/private \
      include/utils \
      out/Release/*.a \
      src/gpu/**/*.h \
      third_party/externals/angle2/include \
      third_party/skcms/**/*.h
  '';
}
