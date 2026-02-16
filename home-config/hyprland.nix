{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;

    settings = {
      "$mainMod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "hyprlauncher";
      "$fileManager" = "nemo";

      exec-once = "$menu -d";

      monitor = ",preffered,auto,auto";

      monitorv2 = {
        output = "DP-2";
        mode = "2560x1440@180";
        position = "0x0";
        scale = 1;
        cm = "auto";
        bitdepth = 8;
        sdr_min_luminance = 0.005;
        sdr_max_luminance = 200;
        min_luminance = 1;
        max_luminance = 1000;
        max_avg_luminance = 1000;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 0;
        #"col.active_border" = "rgba(33ccffee)";
        #"col.inactive_border" = "rgba(595959aa)";
        resize_on_border = true;
        allow_tearing = true;
        layout = "dwindle";
      };

      decoration = {
        rounding = 15;
        rounding_power = 2;
        active_opacity = 1.0;
        inactive_opacity = 0.85;

        shadow = {
          enabled = true;
          range = 15;
          render_power = 3;
          #color = "rgba(1a1a1a55)";
        };

        blur = {
          enabled = true;
          size = 4;
          passes = 3;
          vibrancy = 0.1696;
        };
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        force_default_wallpaper = 1;
        disable_hyprland_logo = true;
        vrr = 1;
        animate_manual_resizes = true;
      };

      #quirks = {
      #  prefer_hdr = 1;
      #};

      input = {
        kb_layout = "us,ru";
        kb_options = "grp:win_space_toggle";
        repeat_delay = 250;
        accel_profile = "flat";
        scroll_factor = 1.4;
      };

      windowrule = [
        "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
      ];

      bind = [
        "$mainMod, RETURN, exec, $terminal"
        "$mainMod, Q, killactive,"
        "$mainMod, M, exit,"
        "$mainMod, R, exec, $fileManager"
        "$mainMod, T, togglefloating,"
        "$mainMod, E, exec, $menu"
        "$mainMod, P, pseudo, # dwindle"
        "$mainMod, J, togglesplit, # dwindle"
        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"
        "$mainMod, F, fullscreen,"
        "$mainMod SHIFT, T, workspaceopt, allfloat"
        "$mainMod ALT, left, swapwindow, l"
        "$mainMod ALT, right, swapwindow, r"
        "$mainMod ALT, up, swapwindow, u"
        "$mainMod ALT, down, swapwindow, d"
      ]
      ++ (
        # workspaces
        # binds $mod + [shift +] {1..9} to [move to] workspace {1..9}
        builtins.concatLists (builtins.genList (i:
            let ws = i + 1;
            in [
              "$mainMod, code:1${toString i}, workspace, ${toString ws}"
              "$mainMod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
            ]
          )
        9)
      );

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      ];

      bindl = [
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };
}
