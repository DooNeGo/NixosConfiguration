{
  # Files created by one of the users sharing the repo stay writable for the other (umask alone gives 644).
  # `A+` is recursive and also sets the default ACL, so later files inherit it; it is applied on every switch and boot.
  systemd.tmpfiles.rules = [
    "A+ /home/shared/NixosConfiguration - - - - g:users:rwX,d:g:users:rwX"
  ];
}
