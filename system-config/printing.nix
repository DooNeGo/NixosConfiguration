{ pkgs, ... }: {
  services = {
    printing = {
      enable = true;
      drivers = with pkgs; [
        gutenprintBin
        gutenprint
        cnijfilter2
        cups-filters
        cups-browsed
      ];
      listenAddresses = [ "*:631" ];
      allowFrom = [ "all" ];
      browsing = true;
      defaultShared = true;
      openFirewall = true;
    };

    ipp-usb.enable = true;

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };
}
