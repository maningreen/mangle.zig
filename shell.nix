{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  packages = with pkgs; [
    zig
    clang
    libGL
    glfw

    libX11
    libX11.dev
    libXcursor
    libXi
    libXinerama
    libXrandr
  ];
}
