{
  targets = {
    "x86_64-unknown-linux-gnu" = {
      pkgsCross = "gnu64";
      triple = "x86_64-unknown-linux-gnu";
    };
    "aarch64-unknown-linux-gnu" = {
      pkgsCross = "aarch64-multiplatform";
      triple = "aarch64-unknown-linux-gnu";
    };
    "x86_64-unknown-linux-musl" = {
      pkgsCross = "musl64";
      triple = "x86_64-unknown-linux-musl";
    };
    "aarch64-unknown-linux-musl" = {
      pkgsCross = "aarch64-multiplatform-musl";
      triple = "aarch64-unknown-linux-musl";
    };
    "x86_64-pc-windows-gnu" = {
      pkgsCross = "mingwW64";
      triple = "x86_64-pc-windows-gnu";
    };
    "x86_64-pc-windows-msvc" = {
      pkgsCross = "x86_64-windows-msvc";
      triple = "x86_64-pc-windows-msvc";
    };
    "x86_64-unknown-freebsd14" = {
      pkgsCross = "freebsd14_x86_64";
      triple = "x86_64-unknown-freebsd14";
    };
    "x86_64-apple-darwin" = {
      pkgsCross = "x86_64-darwin";
      triple = "x86_64-apple-darwin";
    };
    "aarch64-apple-darwin" = {
      pkgsCross = "aarch64-darwin";
      triple = "aarch64-apple-darwin";
    };
  };
}
