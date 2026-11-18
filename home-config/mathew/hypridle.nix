let
  # Only DP-2: HEADLESS-1 is the stream the Sunshine session captures and must stay on.
  dpms = action: "hyprctl dispatch 'hl.dsp.dpms({ monitor = \"DP-2\", action = \"${action}\" })'";
in
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = dpms "enable";
      };

      listener = [
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 610;
          on-timeout = dpms "disable";
          on-resume = dpms "enable";
        }
      ];
    };
  };
}
