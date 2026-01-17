{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [ "network" "wireplumber" "tray" ];

        "hyprland/workspaces" = {
          show-special = true;
          format = "{icon} {windows}";
          persistent-workspaces = {
            "*" = 5;
          };
          workspace-taskbar = {
            enable = true;
            icon-size = 20;
            format = "{icon}";
          };
        };

        tray = {
          icon-size = 20;
          spacing = 10;
        };

        network = {
          format = "{icon} {ifname}";
          tooltip-format = "{ipaddr}";
        };

        wireplumber = {
          format = "{icon} {volume}%";
        };
      };
    };
    style = ''
      window#waybar {
        border-radius: 1em;
        margin: 0.5em;
        background: rgba(10, 10, 10, 0.5);
      }

      #workspaces button {
        padding: 0.1em 0.5em;
        background-color: #1111FF;
        color: #FFFFFF;
        border-radius: 1em;
      }

      #workspaces button.active {
        color: #00FF00;
      }

      /* #workspaces button.visible {
      } */

      #workspaces .workspace-label {
        font-size: 10pt;
      }

      #workspaces .taskbar-window {
        margin: 0;
      }

      #wireplumber {
        color: @white;
      }

      #network {
        color: @white;
      }

      #clock {
        color: @white;
      }

      .modules-right {
        margin: 0.5em;
      }
    '';
  };
}
