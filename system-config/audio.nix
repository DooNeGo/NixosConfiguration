{ pkgs, ... }: {
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    jack.enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };

    extraConfig.pipewire."92-sample-rate" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 352800 384000 ];
        "default.clock.min-quantum" = 32;
        "default.clock.max-quantum" = 8192;
        "default.clock.quantum" = 256;
      };
    };
  };

  services.pipewire.extraConfig.pipewire."99-spatializer-7-1-4" = {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        flags = [ "nofail" ];
        args = let
          sofaPath = ../EAC_48kHz.sofa; 
          radius = 1.2;

          mkSofa = name: az: el: {
            type = "sofa";
            label = "spatializer";
            inherit name;
            config = { filename = sofaPath; };
            control = {
              "Azimuth" = az;
              "Elevation" = el;
              "Radius" = radius;
            };
          };
  
          speakers = [
            { n = "spFL"; a = 35.0; e = 0.0; }
            { n = "spFR"; a = 325.0; e = 0.0; }
            { n = "spFC"; a = 0.0; e = 0.0; }
            { n = "spLFE"; a = 0.0; e = -45.0; }

            { n = "spRL"; a = 150.0; e = 0.0; }
            { n = "spRR"; a = 210.0; e = 0.0; }

            { n = "spSL"; a = 100.0; e = 0.0; }
            { n = "spSR"; a = 260.0; e = 0.0; }

            { n = "spTFL"; a = 45.0; e = 80.0; }
            { n = "spTFR"; a = 315.0; e = 80.0; }
            { n = "spTRL"; a = 135.0; e = 80.0; }
            { n = "spTRR"; a = 225.0; e = 80.0; }
          ];
  
          mixers = map (name: { type = "builtin"; label = "mixer"; inherit name; }) 
                   [ "mixTL" "mixTR" "mixBL" "mixBR" "mixL" "mixR" ];
  
        in {
          "node.description" = "7.1.4 Surround Sound";
          "media.name"       = "7.1.4 Surround Sound";
          
          "filter.graph" = {
            nodes = (map (s: mkSofa s.n s.a s.e) speakers) ++ mixers;
  
            links = [
              { output = "mixBL:Out"; input = "mixL:In 1"; }
              { output = "mixTL:Out"; input = "mixL:In 2"; }
              { output = "mixBR:Out"; input = "mixR:In 1"; }
              { output = "mixTR:Out"; input = "mixR:In 2"; }
            ] 
            ++ (builtins.genList (i: { 
              output = "${(builtins.elemAt speakers i).n}:Out L"; 
              input = "mixBL:In ${toString (i + 1)}"; 
            }) 8)
            ++ (builtins.genList (i: { 
              output = "${(builtins.elemAt speakers i).n}:Out R"; 
              input = "mixBR:In ${toString (i + 1)}"; 
            }) 8)
            ++ (builtins.genList (i: { 
              output = "${(builtins.elemAt speakers (i + 8)).n}:Out L"; 
              input = "mixTL:In ${toString (i + 1)}"; 
            }) 4)
            ++ (builtins.genList (i: { 
              output = "${(builtins.elemAt speakers (i + 8)).n}:Out R"; 
              input = "mixTR:In ${toString (i + 1)}"; 
            }) 4);
  
            inputs  = map (s: "${s.n}:In") speakers;
            outputs = [ "mixL:Out" "mixR:Out" ];
          };
  
          "capture.props" = {
            "node.name"      = "effect_input.spatializer";
            "media.class"    = "Audio/Sink";
            "audio.rate"     = 48000;
            "audio.channels" = 12;
            "audio.position" = [ "FL" "FR" "FC" "LFE" "RL" "RR" "SL" "SR" "TFL" "TFR" "TRL" "TRR" ];
          };
  
          "playback.props" = {
            "node.name"      = "effect_output.spatializer";
            "node.passive"   = true;
            "audio.rate"     = 48000;
            "audio.channels" = 2;
            "audio.position" = [ "FL" "FR" ];
          };
        };
      }
    ];
  };

  services.pipewire.extraConfig.pipewire."99-virtual-surround-71" = {
    "context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "Hesuvi 7.1 Surround";
          "capture.props" = {
            "node.name" = "virtual-surround-71-sink";
            "media.class" = "Audio/Sink";
            "audio.channels" = 8;
            "audio.position" = [ "FL" "FR" "FC" "LFE" "RL" "RR" "SL" "SR" ];
          };
          "playback.props" = {
            "node.name" = "virtual-surround-71-source";
            "audio.channels" = 8;
            "audio.position" = [ "FL" "FR" "FC" "LFE" "RL" "RR" "SL" "SR" ];
            "target.object" = "effect_input.virtual-surround-7.1-hesuvi-48k";
          };
        };
      }
    ];
  };

  services.pipewire.extraConfig.pipewire."97-null-sink" = {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "Null-Sink";
          "node.description" = "Null Sink";
          "media.class" = "Audio/Sink";
          "audio.position" = "FL,FR";
        };
      }
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "Null-Source";
          "node.description" = "Null Source";
          "media.class" = "Audio/Source";
          "audio.position" = "FL,FR";
        };
      }
    ];
  };

  services.pipewire.extraConfig.pipewire."98-virtual-mic" = {
    "context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "audio.position" = "FL,FR";
          "node.description" = "Mumble as Microphone";
          "capture.props" = {
            # Mumble's output node name.
            "node.target" = "Mumble";
            "node.passive" = true;
          };
          "playback.props" = {
            "node.name" = "Virtual-Mumble-Microphone";
            "media.class" = "Audio/Source";
          };
        };
      }
    ];
  };

  services.murmur = {
    enable = true;
    bandwidth = 540000;
    bonjour = true;
    password = "562389";
    autobanTime = 0;
  };

  networking.firewall.allowedTCPPorts = [
    64738
  ];

  networking.firewall.allowedUDPPorts = [
    64738
  ];
}
