{ pkgs, ... }: {
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprintBin
      gutenprint
      cups-filters
      cups-browsed
    ];
  };
}
