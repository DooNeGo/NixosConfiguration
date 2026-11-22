let
  # deadnix: skip
  user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINuQx/6RvkPpbhe5ZevifNT7jgw+T1bLBGDJMYpijdDQ mathew@nixos";
  host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILT46ixfTsT0pc9h+vw1qp8S8v/9fE7A0CHcVmfEyobH root@nixos";
in
{
  "secrets/murmur-password.age".publicKeys = [
    host
  ];
  "secrets/mathew-password.age".publicKeys = [
    host
  ];
  "secrets/vless-credits.age".publicKeys = [
    host
  ];
  "secrets/awg-main.age".publicKeys = [
    host
  ];
  "secrets/vless-test.age".publicKeys = [
    host
  ];
}
