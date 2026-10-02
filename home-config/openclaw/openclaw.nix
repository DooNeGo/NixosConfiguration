{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = import ./local/ai/models.nix;
  aiServer = "100.114.127.10";
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
    ];

    environment.OPENROUTER_API_KEY =
      "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";

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

      models.providers.vllm = {
        baseUrl = "http://${aiServer}:${toString cfg.llmPort}/v1";
        apiKey = "EMPTY";
        timeoutSeconds = 900;
      };

      agents = {
        defaults = {
          model = {
            primary = "openrouter/xiaomi/mimo-v2.6-flash";
            fallbacks = [
              "vllm/${cfg.llmModel}"
              "openrouter/free"
            ];
          };

          models = {
            "vllm/${cfg.llmModel}".params.thinking = "low";
            "openrouter/~z-ai/glm-flash-latest".params.thinking = "high";
          };

          utilityModel = "vllm/${cfg.llmModel}";
          heartbeat.model = "vllm/${cfg.llmModel}";

          # Replaces the retired agents.entries.*.default marker
          # (OpenClaw 2026.9.5 migration): ambient/system work owner,
          # upgraded credential inheritance, and legacy session-store owner.
          systemAgent.agentId = "coordinator";
          authInheritance.agentId = "coordinator";
          sessionStore.agentId = "coordinator";

          userTimezone = "Europe/Minsk";
          params.preserveThinking = true;

          compaction = {
            notifyUser = true;
            midTurnPrecheck.enabled = true;
          };

          subagents = {
            allowAgents = [ ];
            maxSpawnDepth = 2;
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

            workspace = "~/.openclaw/workspace/coordinator";
            
            tools.deny = [
              "browser" "node_inference"
              "dir_fetch" "dir_list" "file_fetch" "file_write"
              "image_generate" "music_generate" "video_generate"
              "github_identity_status"
            ];

            model = {
              primary = "openrouter/~z-ai/glm-flash-latest";

              fallbacks = [
                "vllm/${cfg.llmModel}"
                "openrouter/free"
              ];
            };

            subagents = {
              delegationMode = "prefer";
              allowAgents = [ "worker" "coder" ];
            };
          };

          worker = {
            identity = {
              name = "Scuttle";
              emoji = "🦐";
            };

            workspace = "~/.openclaw/workspace/worker";

            tools = {
              allow = [
                "read" "write" "edit" "apply_patch" "ls"
                "exec" "process"
                "web_search" "web_fetch"
                "view_image" "pdf"
                "memory_search" "memory_get"
                "lcm_grep" "lcm_describe" "lcm_expand" "lcm_expand_query"
                "browser"
                "tts" "talk_voice" "transcripts"
              ];
            };
          };

          coder = {
            identity = {
              name = "Pinch";
              emoji = "🦀";
            };

            workspace = "~/.openclaw/workspace/coder";

            skills = [
              "tmux"
              "python-debugpy"
              "spike"
              "node-inspect-debugger"
              "code-mode-guest"
            ];

            tools = {
              # Code Mode: "auto" engages only for catalog-preferred models
              # (docs/tools/code-mode). mimo-v2.6-flash is NOT preferred —
              # но пользователь 14:12 распорядился форсировать codeMode=true:
              # live-тест 14:14 пройден 6/6 (baseline без скилла). Если
              # падения вернутся — вернуться к "auto".
              codeMode.enabled = true;

              allow = [
                "ls" "read" "write" "edit" "apply_patch"
                "exec" "process"
                "memory_search" "memory_get"
              ];
            };
          };
        };
      };

      # Replaces the retired default marker's channel-wide routing:
      # with 3 agents and no default, inbound telegram needs an explicit
      # binding (docs/gateway/config-agents/entries-and-multi-agent.md).
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
          searxng = {
            enabled = true;
            config.webSearch.baseUrl = "http://${aiServer}:${toString cfg.searxngPort}";
          };

          "lossless-claw" = {
            enabled = true;
            hooks.allowConversationAccess = true;
            llm = {
              allowModelOverride = true;
              allowedModels = [ "openrouter/xiaomi/mimo-v2.6-flash" ];
            };
            config = {
              contextThreshold = 0.06;
              contextThresholdOverrides = [
                {
                  name = "large-context-models";
                  match.modelContextWindowMin = 900000;
                  contextThreshold = 0.06;
                }
              ];
              leafChunkTokens = 12000;
              summaryModel = "openrouter/xiaomi/mimo-v2.6-flash";
              expansionModel = "openrouter/xiaomi/mimo-v2.6-flash";
              cacheAwareCompaction.enabled = true;
              ignoreSessionPatterns = [
                "agent:*:cron:**"
                "agent:*:**:active-memory:**"
                "agent:*:dreaming-narrative-**"
              ];
            };
          };
        };
      };

      memory.search = {
        provider = "openai-compatible";
        model = cfg.embeddingModel;
        remote = {
          baseUrl = "http://127.0.0.1:11434/v1";
        };
      };

#      proxy = {
#        proxyUrl = "http://127.0.0.1:${toString cfg.openclaw.singboxPort}";
#      };

      tts = {
        auto = "inbound";
        mode = "final";
        provider = "tts-local-cli";
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

  home.packages = [ pkgs.ffmpeg ];

# Tradeoff: with the generator below, personas land as read-only store
# symlinks; agents cannot edit their own AGENTS/SOUL/IDENTITY/USER files.
# Re-enable this activation script (it rewrites the symlinks into real
# writable files) only if that editability is wanted again.
#  home.activation.replacePersonaSymlinks = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
#    set -euo pipefail
#    for agent in coordinator coder worker; do
#      for f in AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md; do
#        target="$HOME/.openclaw/workspace/$agent/$f"
#        if [ -L "$target" ]; then
#          mkdir -p -- "$(dirname "$target")"
#          cp --remove-destination -- "$target" "$target.tmp$$"
#          mv -- "$target.tmp$$" "$target"
#          chmod 644 -- "$target"
#        fi
#      done
#    done
#  '';

  home.file =
  let
    agents = [ "coordinator" "coder" "worker" ];
    bootstrapFiles = [ "AGENTS.md" "SOUL.md" "IDENTITY.md" "USER.md" ];
    personaFile = agent: file: lib.nameValuePair
      ".openclaw/workspace/${agent}/${file}"
      { source = ./openclaw-local/workspace + "/${agent}/${file}"; force = true; };
  in lib.listToAttrs (lib.concatMap (agent: map (personaFile agent) bootstrapFiles) agents);
}
