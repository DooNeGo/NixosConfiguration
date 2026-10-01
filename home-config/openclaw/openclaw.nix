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

    # NOTE: no OPENCLAW_GATEWAY_TOKEN here on purpose. Gateway auth is
    # delegated to the same-host tailscale-serve loopback proxy
    # (see gateway.auth below). trusted-proxy mode and a shared token are
    # mutually exclusive (dist/auth-BJWqNCCq.mjs:52), and the user asked for
    # tokenless access.

    environment.OPENROUTER_API_KEY =
      "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";

    config = {
      gateway = {
        mode = "local";
        bind = "loopback";

        # NixOS services.tailscale.serve (system-config/remote-access.nix)
        # runs an externally managed reverse proxy: tailnet HTTPS on
        # https://nixos.tail416d29.ts.net -> http://127.0.0.1:18789.
        # That proxy connects from loopback and adds Forwarded / X-Forwarded-*
        # / Tailscale identity headers. Without a trusted source OpenClaw
        # rejects such proxy-shaped traffic with proxy_attribution_required
        # (dist/ingress-attribution-CoTClK-N.mjs:106-113), which is the exact
        # error seen in the browser. Trust the loopback proxy narrowly.
        # Docs: docs/gateway/tailscale.md "Externally managed Serve and Funnel",
        # docs/gateway/trusted-proxy-auth.md.
        trustedProxies = [ "127.0.0.1" ];

        auth = {
          # Tokenless Control UI / WebSocket auth: tailscaled injects the
          # verified tailnet identity in the tailscale-user-login header on
          # served requests; OpenClaw reads it as the trusted-proxy identity.
          # Loopback sources are only accepted with an explicit allowLoopback
          # opt-in (dist/auth-BJWqNCCq.mjs:64). Docs:
          # docs/gateway/trusted-proxy-auth.md.
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

          # Local direct fallback for same-host CLI callers (openclaw devices
          # approve, openclaw gateway status, ...). trusted-proxy mode forbids a
          # shared token, but internal same-host callers may use a password
          # (docs/gateway/trusted-proxy-auth.md "Mixed token configuration";
          # docs/gateway/config-gateway.md:144). The password is a SecretRef to
          # a file outside the Nix store, so no plaintext lands in the generated
          # config; both the gateway process and the CLI (which reads
          # ~/.openclaw/openclaw.json) resolve it via the file provider below.
          password = {
            source = "file";
            provider = "local-gateway-password";
            id = "value";
          };

          # Session-only operator scope grant for the verified tailnet identity
          # that tailscaled injects as tailscale-user-login on served requests.
          # Lets the browser Devices page approve devices without a manual
          # host-side approval. Docs: docs/gateway/config-gateway.md:146,
          # docs/gateway/trusted-proxy-auth.md ("Per-identity scope grants").
          identityScopes = {
            "matveyprostomac@gmail.com" = [ "operator.admin" ];
          };
        };
      };

      # File secret provider backing gateway.auth.password above. mode
      # "singleValue" makes the whole file the secret (the ref id must be
      # "value"). The file lives at ~/.secrets/... (0600, a real file, not a
      # store symlink) and is read by OpenClaw at runtime.
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
