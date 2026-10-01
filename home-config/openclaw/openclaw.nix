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

    environment.OPENCLAW_GATEWAY_TOKEN =
      "${config.home.homeDirectory}/.secrets/openclaw-gateway-token";

    environment.OPENROUTER_API_KEY =
      "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";

    config = {
      gateway = {
        mode = "local";
        bind = "loopback";
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
            # deny-based (allow would silently drop new core tools on
            # upgrades). Voice tools (tts/talk_voice/transcripts) stay:
            # the user sends voice requests. canvas/dashboard/progress_card
            # stay: they render in the WebUI the user runs.
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
                # files
                "read" "write" "edit" "apply_patch" "ls"
                # runtime (long/background shell jobs)
                "exec" "process"
                # web research (searxng)
                "web_search" "web_fetch"
                # reading fetched content
                "view_image" "pdf"
                # memory recall
                "memory_search" "memory_get"
                # lossless-claw recall after compaction
                "lcm_grep" "lcm_describe" "lcm_expand" "lcm_expand_query"
                # web automation (scraping, screenshots, login flows)
                "browser"
                # voice in/out (user uses voice requests)
                "tts" "talk_voice" "transcripts"
              ];
              deny = [
                # children never delegate further
                "sessions_spawn" "sessions_send" "subagents"
                "agents_list" "agents_wait" "sessions_yield"
                # no direct user contact
                "message" "ask_user"
                # media generation
                "image_generate" "music_generate" "video_generate"
                # not for an executor role
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
                # group:fs - code/config edits
                "ls" "read" "write" "edit" "apply_patch"
                # shell: nix builds, git, tests, long jobs
                "exec" "process"
                # mandated recall + memory/ file workflow
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
