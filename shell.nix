{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  packages = with pkgs; [
    zig
    libGL
    glfw

    libx11
    libx11.dev
    libxcursor
    libxi
    libxinerama
    libxrandr
  ];
}
