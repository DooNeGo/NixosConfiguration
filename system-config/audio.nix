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
        "default.clock.min-quantum" = 256;
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
          sofaPath = ../H14_48K_24bit_256tap_FIR_SOFA.sofa;
          #sofaPath = ../EAC_48kHz.sofa;
          #sofaPath = ../D2_48K_24bit_256tap_FIR_SOFA.sofa;
          radius = 1.2;
  
          mkSofa = name: az: el: {
            type = "sofa";
            label = "spatializer";
            inherit name;
            config.filename = sofaPath;
            control = {
              "Azimuth"   = az;
              "Elevation" = el;
              "Radius"    = radius;
            };
          };
  
          speakers = [
            { n = "spFL";  a = 26.0;  e = 0.0; }
            { n = "spFR";  a = 334.0; e = 0.0; }
            { n = "spFC";  a = 0.0;   e = 0.0; }
            { n = "spRL";  a = 140.0; e = 0.0; }
            { n = "spRR";  a = 220.0; e = 0.0; }
            { n = "spSL";  a = 90.0;  e = 0.0; }
            { n = "spSR";  a = 270.0; e = 0.0; }
            { n = "spTFL"; a = 45.0;  e = 45.0; }
            { n = "spTFR"; a = 315.0; e = 45.0; }
            { n = "spTRL"; a = 135.0; e = 45.0; }
            { n = "spTRR"; a = 225.0; e = 45.0; }
          ];
  
          bedCount    = 7;
          heightCount = 4;
          channelGain = 0.17;
          #channelGain = 1;
  
          mkMixer = name: gain: {
            type = "builtin";
            label = "mixer";
            inherit name;
          } // (if gain != null then {
            control = builtins.listToAttrs (
              builtins.genList (i: {
                name = "Gain ${toString (i + 1)}";
                value = gain;
              }) 8
            );
          } else {});
          
          lfeNodes = [ { type = "builtin"; label = "copy"; name = "copyLFE"; } ];

          subMixers = map (name: mkMixer name channelGain) [ "mixBL" "mixBR" "mixTL" "mixTR" ];
          outMixers = map (name: mkMixer name null) [ "mixL" "mixR" ];
        in {
          "node.description" = "7.1.4 Surround Sound";
          "media.name"       = "7.1.4 Surround Sound";
  
          "filter.graph" = {
            nodes = (map (s: mkSofa s.n s.a s.e) speakers) ++ lfeNodes ++ subMixers ++ outMixers;
  
            links =
              (builtins.genList (i: {
                output = "${(builtins.elemAt speakers i).n}:Out L";
                input  = "mixBL:In ${toString (i + 1)}";
              }) bedCount)

              ++ (builtins.genList (i: {
                output = "${(builtins.elemAt speakers i).n}:Out R";
                input  = "mixBR:In ${toString (i + 1)}";
              }) bedCount)
  
              ++ (builtins.genList (i: {
                output = "${(builtins.elemAt speakers (i + bedCount)).n}:Out L";
                input  = "mixTL:In ${toString (i + 1)}";
              }) heightCount)

              ++ (builtins.genList (i: {
                output = "${(builtins.elemAt speakers (i + bedCount)).n}:Out R";
                input  = "mixTR:In ${toString (i + 1)}";
              }) heightCount)
  
              ++ [
                { output = "mixBL:Out";    input = "mixL:In 1"; }
                { output = "mixTL:Out";    input = "mixL:In 2"; }
                { output = "copyLFE:Out";  input = "mixL:In 3"; }
  
                { output = "mixBR:Out";    input = "mixR:In 1"; }
                { output = "mixTR:Out";    input = "mixR:In 2"; }
                { output = "copyLFE:Out";  input = "mixR:In 3"; }
              ];
  
            inputs = [
              "spFL:In" "spFR:In" "spFC:In" "copyLFE:In"
              "spRL:In" "spRR:In" "spSL:In" "spSR:In"
              "spTFL:In" "spTFR:In" "spTRL:In" "spTRR:In"
            ];
  
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

  services.pipewire.extraConfig.pipewire."98-spatializer-7-1" = {
    "context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "7.1 Surround Sound";
  
          "capture.props" = {
            "node.name"      = "effect_input.spatializer71";
            "media.class"    = "Audio/Sink";
            "audio.channels" = 8;
            "audio.position" = [ "FL" "FR" "FC" "LFE" "RL" "RR" "SL" "SR" ];
          };
  
          "playback.props" = {
            "node.name"      = "effect_output.spatializer71";
            "node.passive"   = true;
            "audio.channels" = 8;
            "audio.position" = [ "FL" "FR" "FC" "LFE" "RL" "RR" "SL" "SR" ];
            "target.object"  = "effect_input.spatializer";
            "stream.dont-remix" = false;
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
