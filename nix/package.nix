{ craneLib, pkgs, system, targetTriple, targetName, ... }:

craneLib.buildPackage {
  pname = "dwm-win32";
  version = "0.1.0";

  src = craneLib.cleanPaths [ ../. ];

  buildInputs = with pkgs; [ ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ libxcb xorg.libX11 xorg.libXinerama xorg.libXft fontconfig freetype ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ]
    ++ lib.optionals stdenv.hostPlatform.isWindows [ ];

  nativeBuildInputs = with pkgs; [ pkg-config ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ];

  strictDeps = true;

  meta = with pkgs.lib; {
    description = "dwm-win32: dwm window manager for Windows";
    homepage = "https://github.com/org/dwm-win32";
    license = licenses.mit;
    platforms = [ targetTriple ];
    mainProgram = "dwm-win32";
  };
}
