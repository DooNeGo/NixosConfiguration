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
  losslessClaw = import ./lossless-claw.nix { inherit pkgs; };
in
{
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    enable = true;

    environment.OPENROUTER_API_KEY =
      "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";

    config = {
      gateway = {
        mode = "local";
        bind = "loopback";

        # Token auth: the gateway token lives in ~/.secrets/openclaw-gateway-token
        # and is referenced via SecretRef (file provider below), so no plaintext
        # lands in the generated config. Both the gateway process and the CLI
        # (which reads ~/.openclaw/openclaw.json) resolve it at runtime.
        # NOTE: tailscale serve ingress is currently disabled
        # (system-config/remote-access.nix) - proxy-shaped traffic requires
        # trusted-proxy auth mode, which is mutually exclusive with a shared
        # token. Re-enable serve only together with the whois path
        # (gateway.tailscale.mode = "serve" + tailscale operator).
        auth = {
          mode = "token";
          token = {
            source = "file";
            provider = "gateway-token-file";
            id = "value";
          };
        };
      };

      # File secret provider backing gateway.auth.token above. mode
      # "singleValue" makes the whole file the secret (the ref id must be
      # "value"). The file lives at ~/.secrets/... (0600, a real file, not a
      # store symlink) and is read by OpenClaw at runtime.
      secrets.providers.gateway-token-file = {
        source = "file";
        path = "${config.home.homeDirectory}/.secrets/openclaw-gateway-token";
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
            primary =
              #"openrouter/~z-ai/glm-flash-latest";
              "vllm/${cfg.llmModel}";
            fallbacks = [
              "openrouter/~deepseek/deepseek-flash-latest"
              "openrouter/qwen/qwen3.8-27b:free"
            ];
          };

          models = {
            "vllm/${cfg.llmModel}".params.thinking = "low";
            "openrouter/qwen/qwen3.8-27b:free".params.thinking = "low";
            "openrouter/~z-ai/glm-flash-latest".params.thinking = "high";
            "openrouter/~deepseek/deepseek-flash-latest".params.thinking = "low";
          };

          utilityModel = "openrouter/qwen/qwen3.8-27b:free";

          userTimezone = "Europe/Minsk";
          params.preserveThinking = true;

          compaction = {
            notifyUser = true;
            midTurnPrecheck.enabled = true;
          };

          subagents.maxSpawnDepth = 2;
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
                "openrouter/~deepseek/deepseek-flash-latest"
                "openrouter/qwen/qwen3.8-27b:free"
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
            subagents.allowAgents = [ ];
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
              deny = [
                "sessions_spawn" "sessions_send" "subagents"
                "agents_list" "agents_wait" "sessions_yield"
                "message" "ask_user"
                "image_generate" "music_generate" "video_generate"
                "skill_workshop" "secrets"
                "create_goal" "update_goal" "get_goal"
              ];
            };
          };

          coder = {
            identity = {
              name = "Pinch";
              emoji = "🦀";
            };

            workspace = "~/.openclaw/workspace/coder";
            subagents.allowAgents = [ ];
            tools = {
              codeMode.enabled = true;
              allow = [
                "ls" "read" "write" "edit" "apply_patch"
                "exec" "process"
                "memory_search" "memory_get"
              ];
              deny = [ "group:messaging" "group:ui" ];
            };
          };
        };
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
        load.paths = [
          "${pkgs.openclawRuntimePlugins.searxng}"
          "${losslessClaw}"
        ];

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
              allowedModels = ["openrouter/qwen/qwen3.8-27b:free"];
            };
            config = {
              contextThreshold = 0.3;
              contextThresholdOverrides = [
                {
                  name = "large-context-models";
                  match.modelContextWindowMin = 900000;
                  contextThreshold = 0.06;
                }
              ];
              leafChunkTokens = 12000;
              summaryModel = "openrouter/qwen/qwen3.8-27b:free";
              expansionModel = "openrouter/qwen/qwen3.8-27b:free";
              cacheAwareCompaction = {
                enabled = true;
                cacheTTLSeconds = 300;
              };
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

  home.activation.replacePersonaSymlinks = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -euo pipefail
    for agent in coordinator coder worker; do
      for f in AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md; do
        target="$HOME/.openclaw/workspace/$agent/$f"
        if [ -L "$target" ]; then
          mkdir -p -- "$(dirname "$target")"
          cp --remove-destination -- "$target" "$target.tmp$$"
          mv -- "$target.tmp$$" "$target"
          chmod 644 -- "$target"
        fi
      done
    done
  '';

  home.file = {
    ".openclaw/workspace/coordinator/AGENTS.md" = { source = ./openclaw-local/workspace/coordinator/AGENTS.md; force = true; };
    ".openclaw/workspace/coordinator/SOUL.md" = { source = ./openclaw-local/workspace/SOUL.md; force = true; };
    ".openclaw/workspace/coordinator/IDENTITY.md" = { source = ./openclaw-local/workspace/IDENTITY.md; force = true; };
    ".openclaw/workspace/coordinator/USER.md" = { source = ./openclaw-local/workspace/USER.md; force = true; };
    ".openclaw/workspace/coordinator/TOOLS.md" = { source = ./openclaw-local/workspace/TOOLS.md; force = true; };

    ".openclaw/workspace/coder/AGENTS.md" = { source = ./openclaw-local/workspace/coder/AGENTS.md; force = true; };
    ".openclaw/workspace/coder/SOUL.md" = { source = ./openclaw-local/workspace/SOUL.md; force = true; };
    ".openclaw/workspace/coder/IDENTITY.md" = { source = ./openclaw-local/workspace/IDENTITY.md; force = true; };
    ".openclaw/workspace/coder/USER.md" = { source = ./openclaw-local/workspace/USER.md; force = true; };
    ".openclaw/workspace/coder/TOOLS.md" = { source = ./openclaw-local/workspace/TOOLS.md; force = true; };

    ".openclaw/workspace/worker/AGENTS.md" = { source = ./openclaw-local/workspace/worker/AGENTS.md; force = true; };
    ".openclaw/workspace/worker/SOUL.md" = { source = ./openclaw-local/workspace/SOUL.md; force = true; };
    ".openclaw/workspace/worker/IDENTITY.md" = { source = ./openclaw-local/workspace/IDENTITY.md; force = true; };
    ".openclaw/workspace/worker/USER.md" = { source = ./openclaw-local/workspace/USER.md; force = true; };
    ".openclaw/workspace/worker/TOOLS.md" = { source = ./openclaw-local/workspace/TOOLS.md; force = true; };
  };
}
