{ config, pkgs, ... }:
let
  # Written by the wallpaper script; the unit seeds the default so the first start finds the import.
  colorsFile = "${config.home.homeDirectory}/.local/state/waybar/colors.css";
  # Waybar reads the config under the full name "custom/sep#N", with no fallback to "custom/sep".
  # A custom module without exec renders only once a worker is started; interval starts it.
  separator = {
    format = "·";
    interval = 3600;
    tooltip = false;
  };
  # Pango markup: glyphs of the right-island indicators share one size, larger than the 13px text.
  # The text beside a glyph is raised (Pango rise, 1/1024 pt) so both share a vertical centre.
  text = t: "<span rise='2000'>${t}</span>";
  iconSize = "x-large";
  icon = glyph: "<span font_size='${iconSize}'>${glyph}</span>";
  coverFile = "${config.home.homeDirectory}/.cache/waybar/media-cover";
  media = pkgs.writeShellApplication {
    name = "waybar-media";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.playerctl
    ];
    runtimeEnv.WAYBAR_MEDIA_COVER = coverFile;
    text = builtins.readFile ./waybar-media.sh;
  };
  mic = pkgs.writeShellApplication {
    name = "waybar-mic";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.pulseaudio
    ];
    runtimeEnv = {
      WAYBAR_MIC_GLYPH_ON = "󰍬";
      WAYBAR_MIC_GLYPH_OFF = "󰍭";
      WAYBAR_MIC_ICON_SIZE = iconSize;
    };
    text = builtins.readFile ./waybar-mic.sh;
  };
  # Empty output hides a custom module: no records, no indicator. The dot before it is a module of its own
  # (same condition) so every gap in the island is built the same way.
  failedUnits = pkgs.writeShellScript "waybar-failed-units" ''
    list=$(failure-notify list 2>/dev/null) || exit 0
    [ -n "$list" ] || exit 0
    if [ "$1" = dot ]; then
      echo '{"text":"·"}'
      exit 0
    fi
    n=$(printf '%s\n' "$list" | wc -l)
    ${pkgs.jq}/bin/jq -cn --arg text "${icon "󰀦"} ${text "$n"}" --arg tip "$list" '{text: $text, tooltip: $tip, class: "failed"}'
  '';
  seedColors = pkgs.writeShellScript "waybar-seed-colors" ''
    [ -e ${colorsFile} ] || ${pkgs.coreutils}/bin/install -D -m 644 ${./waybar-colors-default.css} ${colorsFile}
  '';
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        margin-top = 10;
        margin-left = 10;
        margin-right = 10;
        spacing = 5;
        reload_style_on_change = true;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [
          "clock"
          "custom/media"
        ];
        modules-right = [
          "hyprland/language"
          "custom/sep#1"
          "network"
          "custom/sep#2"
          "wireplumber"
          "custom/mic"
          "custom/failed-dot"
          "custom/failed"
          "custom/sep#3"
          "idle_inhibitor"
          "custom/sep#4"
          "tray"
        ];

        "hyprland/workspaces" = {
          show-special = true;
          format = "{name} {windows}";
          persistent-workspaces = {
            "*" = 5;
          };
          workspace-taskbar = {
            enable = true;
            icon-size = 20;
            format = "{icon}";
            on-click-window = "hyprctl dispatch 'hl.dsp.focus({ window = \"address:{address}\" })'";
          };
        };

        "custom/sep#1" = separator;
        "custom/sep#2" = separator;
        "custom/sep#3" = separator;
        "custom/sep#4" = separator;

        "custom/media" = {
          exec = "${media}/bin/waybar-media";
          return-type = "json";
          escape = true;
          image-path = coverFile;
          icon-size = 24;
          on-click = "${pkgs.playerctl}/bin/playerctl -p playerctld play-pause";
        };

        "custom/failed-dot" = {
          exec = "${failedUnits} dot";
          return-type = "json";
          interval = 60;
        };

        "custom/failed" = {
          exec = "${failedUnits}";
          return-type = "json";
          interval = 60;
          on-click = "kitty --hold failure-notify list";
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = icon "󰅶";
            deactivated = icon "󰾪";
          };
        };

        clock = {
          locale = "ru_RU.UTF-8";
          format = "{:L%H:%M · %d %B}";
          tooltip-format = "{:L%A, %d %B %Y}";
        };

        "hyprland/language" = {
          format = "${icon "󰌌"} ${text "{short}"}";
        };

        tray = {
          icon-size = 20;
          spacing = 10;
        };

        network = {
          format-ethernet = "${icon "󰈀"} ${text "{ifname}"}";
          format-wifi = "${icon "󰖩"} ${text "{essid}"}";
          format-disconnected = "${icon "󰖪"} ${text "offline"}";
          tooltip-format = "{ipaddr}";
        };

        "custom/mic" = {
          exec = "${mic}/bin/waybar-mic";
          return-type = "json";
          on-click = "${mic}/bin/waybar-mic toggle";
        };

        wireplumber = {
          format = "{icon} ${text "{volume}%"}";
          format-muted = "${icon "󰝟"} ${text "muted"}";
          format-icons = [
            (icon "󰕿")
            (icon "󰖀")
            (icon "󰕾")
          ];
        };
      };
    };
    style = builtins.replaceStrings [ "@colors@" ] [ colorsFile ] (builtins.readFile ./waybar.css);
  };

  # Also provides the playerctl binary that the media keys in hyprland.lua call.
  services.playerctld.enable = true;

  systemd.user.services.waybar.Service.ExecStartPre = "${seedColors}";
}
