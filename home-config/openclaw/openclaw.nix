{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = import ./local/ai/models.nix;
in
{
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    enable = true;

    runtimePlugins = [
      "searxng"
      "lossless-claw"
      "tokenjuice"
    ];

    bundledPlugins.summarize.enable = true;

    environment.OPENROUTER_API_KEY = "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";

    skills = [
      {
        name = "kokoro-voice";
        description = "Voice replies via local kokoro-ru TTS (Russian, Telegram).";
        mode = "symlink";
        source = toString ./skills/kokoro-voice;
      }
      {
        name = "skill-vetter";
        description = "Security-first skill vetting for AI agents. Use before installing any skill from ClawdHub, GitHub, or other sources. Checks for red flags, permission scope, and suspicious patterns.";
        mode = "symlink";
        source = toString ./skills/skill-vetter;
      }
      {
        name = "self-improving-agent";
        description = "Captures and maintains learnings, errors, and corrections. Use when a command fails, the user corrects an assumption, a capability is missing, knowledge is outdated, or a better approach is found.";
        mode = "symlink";
        source = toString ./skills/self-improving-agent;
      }
    ];

    workspace.files =
      let
        personaAgents = [
          "coordinator"
          "coder"
          "worker"
          "advisor"
        ];
        personaFiles = [
          "AGENTS.md"
          "SOUL.md"
          "IDENTITY.md"
          "USER.md"
        ];
        personaFile =
          agent: file:
          let
            dir = ./openclaw-local/workspace;
            agentPath = dir + "/${agent}/${file}";
            source = if builtins.readFileType agentPath == "symlink" then dir + "/${file}" else agentPath;
          in
          lib.nameValuePair "${agent}/${file}" source;
      in
      lib.listToAttrs (lib.concatMap (agent: map (personaFile agent) personaFiles) personaAgents);

    config = {
      gateway = {
        mode = "local";
        bind = "loopback";
        trustedProxies = [ "127.0.0.1" ];

        auth = {
          mode = "trusted-proxy";
          trustedProxy = {
            userHeader = "tailscale-user-login";
            requiredHeaders = [
              "x-forwarded-for"
              "x-forwarded-proto"
              "x-forwarded-host"
            ];
            allowLoopback = true;
          };

          password = {
            source = "file";
            provider = "local-gateway-password";
            id = "value";
          };

          identityScopes = {
            "matveyprostomac@gmail.com" = [ "operator.admin" ];
          };
        };
      };

      secrets.providers.local-gateway-password = {
        source = "file";
        path = "${config.home.homeDirectory}/.secrets/openclaw-gateway-password";
        mode = "singleValue";
      };

      session.dmScope = "per-channel-peer";

      channels.telegram = {
        tokenFile = "${config.home.homeDirectory}/.secrets/openclaw-telegram-bot-token";
        richMessages = true;
        allowFrom = [ 760128577 ];
        groups = {
          "*" = {
            requireMention = true;
          };
        };
        streaming = {
          mode = "progress";
          progress = {
            toolProgress = true;
            commandText = "status";
            commentary = true;
          };
        };
      };

#      models.providers.vllm = {
#        baseUrl = "http://${aiServer}:${toString cfg.llmPort}/v1";
#        apiKey = "EMPTY";
#        timeoutSeconds = 900;
#      };

      messages.responseUsage = "full";

      agents = {
        defaults = {
          model = {
            primary = "openrouter/xiaomi/mimo-v2.6-flash";
            fallbacks = [
              #"vllm/${cfg.llmModel}"
              "openrouter/~z-ai/glm-flash-latest"
              "openrouter/free"
            ];
          };

          modelPolicy.allow = [
            "openrouter/xiaomi/mimo-v2.6-flash"
            "openrouter/xiaomi/mimo-v2.6-pro"
            "openrouter/anthropic/claude-sonnet-5-5"
            "openrouter/~z-ai/glm-flash-latest"
            "openrouter/~z-ai/glm-latest"
            "openrouter/free"
          ];

          models = {
            #"vllm/${cfg.llmModel}".params.thinking = "low";
            "openrouter/~z-ai/glm-flash-latest".params.thinking = "high";
            "openrouter/~z-ai/glm-latest".params.thinking = "high";
          };

          #utilityModel = "vllm/${cfg.llmModel}";
          utilityModel = "openrouter/xiaomi/mimo-v2.6-flash";
          #heartbeat.model = "vllm/${cfg.llmModel}";
          heartbeat = {
            model = "openrouter/xiaomi/mimo-v2.6-flash";
            isolatedSession = true;
            lightContext = true;
            every = "0m";
          };

          systemAgent.agentId = "coordinator";
          authInheritance.agentId = "coordinator";
          sessionStore.agentId = "coordinator";

          userTimezone = "Europe/Minsk";
          params.preserveThinking = true;

          compaction = {
            notifyUser = true;
           # midTurnPrecheck.enabled = true;
          };

          subagents = {
            allowAgents = [ ];
            maxSpawnDepth = 1;
            requireAgentId = true;
          };
        };

        entries = {
          coordinator = {
            default = true;

            identity = {
              name = "Claw";
              emoji = "🦞";
            };

            memory.search.rememberAcrossConversations = true;
            heartbeat.every = "1h";

            workspace = "~/.openclaw/workspace/coordinator";

            model = {
              primary = "openrouter/~z-ai/glm-latest";

              fallbacks = [
                "openrouter/~z-ai/glm-flash-latest"
            #    "vllm/${cfg.llmModel}"
                "openrouter/free"
              ];
            };

            subagents = {
              delegationMode = "prefer";
              allowAgents = [
                "worker"
                "coder"
                "advisor"
              ];
            };
          };

          worker = {
            identity = {
              name = "Scuttle";
              emoji = "🦐";
            };

            workspace = "~/.openclaw/workspace/worker";

            skills = [
              "browser-automation" "summarize" "tmux" "python-debugpy"
              "spike" "healthcheck" "self-improving-agent" "visualize"
              "diagram-maker" "weather"
            ];
          };

          coder = {
            identity = {
              name = "Pinch";
              emoji = "🦀";
            };

            workspace = "~/.openclaw/workspace/coder";

            tools = {
              codeMode = "auto";
            };

            skills = [
              "tmux" "python-debugpy" "spike" "summarize"
              "self-improving-agent" "diagram-maker" "visualize"
              "node-inspect-debugger"
            ];
          };

          advisor = {
            identity = {
              name = "Sage";
              emoji = "🧠";
            };

            workspace = "~/.openclaw/workspace/advisor";

            skills = [
              "summarize" "skill-vetter" "browser-automation" "spike"
              "diagram-maker" "visualize" "self-improving-agent"
            ];

            model = {
              primary = "openrouter/anthropic/claude-sonnet-5-5";
              fallbacks = [ "openrouter/xiaomi/mimo-v2.6-pro" ];
            };

            modelPolicy.allow = [
              "openrouter/anthropic/claude-sonnet-5-5"
              "openrouter/xiaomi/mimo-v2.6-pro"
            ];
          };
        };
      };

      bindings = [
        {
          agentId = "coordinator";
          match = {
            channel = "telegram";
            accountId = "*";
          };
        }
      ];

      talk = {
        agentId = "coordinator";
      };

      tools.web.search.provider = "searxng";

      # Skills disabled 2026-10-08: research/2026-10-08-skills-review/REPORT.md
      # + research/2026-10-08-per-agent-skills-scope/REPORT.md (Pareto,
      # 41-name denylist minus node-inspect-debugger pending advisor decision).
      # Soft disable; drop a name to restore.
      skills.entries = lib.listToAttrs (
        map (n: lib.nameValuePair n { enabled = false; }) [
          "1password" "apple-notes" "apple-reminders" "bear-notes"
          "blogwatcher" "blucli" "camsnap" "canvas" "cloud-image-bake"
          "coding-agent" "control-ui" "eightctl" "gemini" "gh-issues"
          "gifgrep" "github" "goplaces" "himalaya" "meme-maker" "mcporter"
          "model-usage" "nano-pdf" "notion" "obsidian"
          "openai-whisper" "openai-whisper-api" "openhue" "oracle" "ordercli"
          "peekaboo" "sag" "sherpa-onnx-tts" "songsee" "sonoscli"
          "spotify-player" "taskflow" "taskflow-inbox-triage" "things-mac"
          "trello" "xurl"
        ]
      );

      tools.media = {
        models = [
          {
            type = "cli";
            command = "${pkgs.whisper-cpp}/bin/whisper-cli";
            args = [
              "-m"
              "${config.home.homeDirectory}/.local/share/whisper-models/ggml-small.bin"
              "-l"
              "ru"
              "-nt"
              "-np"
              "{{AttachmentPath}}"
            ];
            capabilities = [ "audio" ];
            timeoutSeconds = 120;
            maxBytes = 20971520;
          }
        ];

        audio = {
          enabled = true;
          language = "ru";
          timeoutSeconds = 120;
          echoTranscript = false;
        };
      };

      plugins = {
        slots.contextEngine = "lossless-claw";

        entries = {
          # channel plugin carries this live Telegram session but the plugin
          # registry reports it disabled — persist the enable (Q4 FIX 1)
          telegram = {
            enabled = true;
          };

          searxng = {
            enabled = true;
            config.webSearch.baseUrl = "http://localhost:6080";
          };

          "lossless-claw" = {
            enabled = true;
            hooks.allowConversationAccess = true;
            llm = {
              allowModelOverride = true;
              allowedModels = [
                "openrouter/xiaomi/mimo-v2.6-flash"
                #"vllm/${cfg.llmModel}"
              ];
            };
            # migrated 2026-10-08 from legacy config.expansionModel
            # (doctor preview: subagent.allowModelOverride + allowedModels)
            subagent = {
              allowModelOverride = true;
              allowedModels = [
                "openrouter/xiaomi/mimo-v2.6-flash"
              ];
            };
            config = {
              #contextThreshold = 0.25;
              maxAssemblyTokenBudget = 100000;
              freshTailMaxTokens = 24000;
              summaryMaxCallsPerWindow = 48;
              #summaryModel = "vllm/${cfg.llmModel}";
              summaryModel = "openrouter/xiaomi/mimo-v2.6-flash";
              cacheAwareCompaction.enabled = true;
              ignoreSessionPatterns = [
                "agent:*:cron:**"
                "agent:*:**:active-memory:**"
                "agent:*:dreaming-narrative-**"
              ];
            };
          };

          "active-memory" = {
            enabled = true;
            config = {
              mode = "escalate";
              agents = [ "coordinator" ];
              logging = true;
            };
          };

        }

        # Disabled 2026-10-08 per research/2026-10-08-plugin-config-review
        # (REPORT.md Q4): unused bundled provider/media plugins — no config,
        # no key material, no references in live settings. canvas stays
        # enabled (paired macOS node); anthropic/google/linux-node stay
        # enabled pending verification (Q4 VERIFY list). Same generation
        # pattern as the skills.entries disable list above.
        // lib.listToAttrs (
          map (n: lib.nameValuePair n { enabled = false; }) [
            "alibaba"
            "azure-speech"
            "clawrouter"
            "copilot-proxy"
            "cua-computer"
            "deepgram"
            "elevenlabs"
            "fal"
            "geolocation"
            "github-copilot"
            "huggingface"
            "litellm"
            "lmstudio"
            "microsoft"
            "microsoft-foundry"
            "minimax"
            "nvidia"
            "openai"
            "opencode-go"
            "runway"
            "senseaudio"
            "sglang"
            "together"
            "vllm"
            "xai"
          ]
        );
      };

      memory.search = {
        provider = "openai-compatible";
        model = cfg.embeddingModel;
        remote = {
          baseUrl = "http://127.0.0.1:11434/v1";
        };
      };

      proxy = {
        proxyUrl = "http://127.0.0.1:${toString cfg.openclaw.singboxPort}";
      };

      # gateway service runs with a stripped PATH and cannot discover
      # ~/.nix-profile/bin/chromium (ungoogled-chromium); point it explicitly
      browser = {
        executablePath = "/home/openclaw/.nix-profile/bin/chromium";
      };
    };
  };

  # /tmp is tmpfs: the gateway unit appends stdout to /tmp/openclaw/
  # openclaw-gateway.log and systemd fails to start it without that path
  # (exit 209). nix-openclaw creates the dir only in its activate script,
  # so tmpfiles recreates it on every user-session start.
  systemd.user.tmpfiles.rules = [
    "d /tmp/openclaw 0700 - - -"
  ];

  # nix-openclaw gateway unit fixes:
  # - WantedBy: the unit ships without autostart, so enable it for boot;
  # - TimeoutStopSec 330s: gateway drains up to 300s (docs/gateway/index.md)
  systemd.user.services."openclaw-gateway" = {
    Install.WantedBy = [ "default.target" ];
    Service.TimeoutStopSec = "330";
  };

  home.packages = with pkgs; [ ffmpeg ];
}
