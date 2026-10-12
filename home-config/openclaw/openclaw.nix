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
      "memory-lancedb"
      "tokenjuice"
      "zai"
    ];

    bundledPlugins = {
      summarize.enable = false;
      goplaces.enable = false;
    };

    environment = {
      OPENROUTER_API_KEY = "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";
      ZAI_API_KEY = "${config.home.homeDirectory}/.secrets/zai-api-key";
      # Plugin source builds use os.tmpdir(); /tmp is a 16G tmpfs.
      TMPDIR = "/var/tmp/openclaw";
    };

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
        name = "ai-chat-bot-admin-access";
        description = "ai-chat-bot on ai-server — service status, last request via admin /logs, reproduce failing request. Bot lives in /home/admin/configuration/chat-bot, unit ai-chat-bot.service, port 5000.";
        mode = "symlink";
        source = toString ./skills/ai-chat-bot-admin-access;
      }
      {
        name = "ai-chat-bot-classifier";
        description = "ai-chat-bot on ai-server — fix classifier misrouting of context-dependent follow-ups, multi-label composition rule, off_topic refusal cost analysis.";
        mode = "symlink";
        source = toString ./skills/ai-chat-bot-classifier;
      }
      {
        name = "ai-chat-bot-debugging";
        description = "ai-chat-bot on ai-server misbehaves — last request via admin /logs, KB junk/duplicated chunks, or rebuild/verify airport_kb (pages missing, garbage).";
        mode = "symlink";
        source = toString ./skills/ai-chat-bot-debugging;
      }
      {
        name = "ai-chat-bot-kb-management";
        description = "ai-chat-bot on ai-server — rebuild/verify the airport_kb Qdrant collection, diagnose KB junk-chunk contamination, indexer pipeline facts. Same host/repo: /home/admin/configuration/chat-bot.";
        mode = "symlink";
        source = toString ./skills/ai-chat-bot-kb-management;
      }
      {
        name = "cross-user-gateway-access";
        description = "Reach an OpenClaw Gateway from a second OS user — ACP/IDE bridge, token handover, client binary install.";
        mode = "symlink";
        source = toString ./skills/cross-user-gateway-access;
      }
      {
        name = "head-to-head-model-test";
        description = "Compare two live LLM endpoints (local vLLM vs OpenRouter) on coding and tool-calling with deterministic scorers — use when asked which model is better.";
        mode = "symlink";
        source = toString ./skills/head-to-head-model-test;
      }
      {
        name = "lossless-compaction-threshold";
        description = "lossless-claw produced no summaries, or context grows unchecked — read the plugin log, compute the threshold vs the model's window, set a working one.";
        mode = "symlink";
        source = toString ./skills/lossless-compaction-threshold;
      }
      {
        name = "mac-mini-gateway-ops";
        description = "Remote OpenClaw administration on the Mac-mini node — plugin installs, config edits, gateway stop/start; \"on the Mac-mini...\" plugin/config tasks.";
        mode = "symlink";
        source = toString ./skills/mac-mini-gateway-ops;
      }
      {
        name = "mac-mini-gog-auth";
        description = "Mac-mini node — Google account auth (gog) invalid_client recovery; probe client secret in keyring, import fresh secret, final OAuth.";
        mode = "symlink";
        source = toString ./skills/mac-mini-gog-auth;
      }
      {
        name = "mac-mini-node-ops";
        description = "Remote OpenClaw administration on the Mac-mini node — plugin installs, config edits, gateway stop/start, provider timeouts; \"on the Mac-mini…\" tasks.";
        mode = "symlink";
        source = toString ./skills/mac-mini-node-ops;
      }
      {
        name = "mac-mini-provider-timeouts";
        description = "Mac-mini node — diagnose model/provider timeouts (agent slow to reply, model-fetch errors), test both OpenAI APIs, set correct api in config.";
        mode = "symlink";
        source = toString ./skills/mac-mini-provider-timeouts;
      }
      {
        name = "workshop-skill-authoring";
        description = "Create or update coordinator skills via skill_workshop — 160-byte description cap, patch rejected for unused skills, update+apply route.";
        mode = "symlink";
        source = toString ./skills/workshop-skill-authoring;
      }
      {
        name = "self-improving-agent";
        description = "Captures and maintains learnings, errors, and corrections. Use when a command fails, the user corrects an assumption, a capability is missing, knowledge is outdated, or a better approach is found.";
        mode = "symlink";
        source = toString ./skills/self-improving-agent;
      }
      {
        name = "nix-openclaw-config";
        description = "Change a Nix-managed OpenClaw setting (reasoning, models, providers, channels) - edit source, eval, apply with consent; ghost home-manager units.";
        mode = "symlink";
        source = toString ./skills/nix-openclaw-config;
      }
      {
        name = "nixos-system-config";
        description = "Edit the NixOS system config (system-config/*.nix) - upstream option check, toplevel build verify, user applies via nixos-rebuild switch.";
        mode = "symlink";
        source = toString ./skills/nixos-system-config;
      }
      {
        name = "nix-dev-env-tooling";
        description = "Nix/NixOS tooling pitfalls - Android SDK license eval, JetBrains Gateway IDE detection, remote hosts missing PATH tools, foreign binaries (stub-ld).";
        mode = "symlink";
        source = toString ./skills/nix-dev-env-tooling;
      }
      {
        name = "maui-android-build";
        description = "Build the MAUI Android app (Wallet.Droid in ~/projects/maui) on NixOS - regenerate tool wrappers, Directory.Build.props build, fix the stale R.java crash.";
        mode = "symlink";
        source = toString ./skills/maui-android-build;
      }
      {
        name = "resilient-delegated-batch";
        description = "Long delegated batch work a restart, model cut, or timeout can kill - persist every unit immediately, order phases by value, resume from the kept session.";
        mode = "symlink";
        source = toString ./skills/resilient-delegated-batch;
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
      lib.listToAttrs (
        lib.concatMap (
          agent:
          map (personaFile agent) (
            lib.filter (file: builtins.pathExists (./openclaw-local/workspace + "/${agent}/${file}")) personaFiles
          )
        ) personaAgents
      );

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

      models.providers = {
        vllm = {
          baseUrl = "http://100.114.127.10:${toString cfg.llmPort}/v1";
          timeoutSeconds = 900;
        };

        zai.baseUrl = "https://api.z.ai/api/coding/paas/v4";
      };

      #messages.responseUsage = "full";

      agents = {
        defaults = {
          model = {
            primary = "zai/glm-5.3-flash";
            fallbacks = [
              "anthropic/claude-haiku-5-5"
              "openrouter/free"
            ];
          };

          models =
            let
              claudes = [
                "claude-haiku-5-5"
                "claude-sonnet-5-5"
                "claude-opus-5-5"
              ];
            in
            {
              "zai/glm-5.3-flash".params.thinking = "low";
              "zai/glm-5.3".params.thinking = "low";
            }
            // lib.listToAttrs (
              map (
                claude:
                lib.nameValuePair "anthropic/${claude}" {
                  agentRuntime.id = "claude-cli";
                  params.thinking = "medium";
                }
              ) claudes
            );

          utilityModel = "zai/glm-5.3-flash";

          heartbeat = {
            model = "zai/glm-5.3-flash";
            isolatedSession = true;
            lightContext = true;
            every = "0m";
          };

          systemAgent.agentId = "coordinator";
          authInheritance.agentId = "coordinator";
          sessionStore.agentId = "coordinator";

          userTimezone = "Europe/Minsk";

          compaction = {
            notifyUser = true;
            midTurnPrecheck.enabled = true;
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

            #heartbeat.every = "2h";

            workspace = "~/.openclaw/workspace/coordinator";

            subagents = {
              delegationMode = "prefer";
              allowAgents = [
                "worker"
                "coder"
                "advisor"
              ];
            };

            models."zai/glm-5.3".params.thinking = "high";

            model = {
              primary = "anthropic/claude-sonnet-5-5";
              fallbacks = [
                "zai/glm-5.3"
                "openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-opus-5-5"
              "anthropic/claude-sonnet-5-5"
              "anthropic/claude-haiku-5-5"
              "zai/glm-5.3-flash"
              "zai/glm-5.3"
              "openrouter/free"
            ];
          };

          worker = {
            identity = {
              name = "Scuttle";
              emoji = "🦐";
            };

            workspace = "~/.openclaw/workspace/worker";

            skills = [
              "browser-automation"
              "summarize"
              "tmux"
              "python-debugpy"
              "spike"
              "healthcheck"
              "self-improving-agent"
              "visualize"
              "diagram-maker"
              "weather"
            ];

            model = {
              primary = "anthropic/claude-haiku-5-5";
              fallbacks = [               
                "zai/glm-5.3-flash"
                "openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-sonnet-5-5"
              "anthropic/claude-haiku-5-5"
              "zai/glm-5.3-flash"
              "zai/glm-5.3"
              "openrouter/free"
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
              "tmux"
              "python-debugpy"
              "spike"
              "summarize"
              "self-improving-agent"
              "diagram-maker"
              "visualize"
            ];

            model = {
              primary = "anthropic/claude-haiku-5-5";
              fallbacks = [
                "zai/glm-5.3"
                "openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-sonnet-5-5"
              "anthropic/claude-haiku-5-5"
              "zai/glm-5.3-flash"
              "zai/glm-5.3"
              "openrouter/free"
            ];
          };

          advisor = {
            identity = {
              name = "Sage";
              emoji = "🧠";
            };

            workspace = "~/.openclaw/workspace/advisor";

            skills = [
              "summarize"
              "skill-vetter"
              "browser-automation"
              "spike"
              "diagram-maker"
              "visualize"
              "self-improving-agent"
            ];

            models."zai/glm-5.3".params.thinking = "max";

            model = {
              primary = "anthropic/claude-opus-5-5";
              fallbacks = [
                "zai/glm-5.3"
                "openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-opus-5-5"
              "anthropic/claude-sonnet-5-5"
              "zai/glm-5.3"
              "openrouter/free"
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

      tools.web = {
        search.provider = "searxng";
        fetch.useTrustedEnvProxy = true;
      };

      skills = {
        workshop.autonomous.mode = "auto";

        entries = lib.listToAttrs (
          map (n: lib.nameValuePair n { enabled = false; }) [
            "1password"
            "apple-notes"
            "apple-reminders"
            "bear-notes"
            "blogwatcher"
            "blucli"
            "camsnap"
            "canvas"
            "cloud-image-bake"
            "coding-agent"
            "control-ui"
            "eightctl"
            "gemini"
            "gh-issues"
            "gifgrep"
            "github"
            "goplaces"
            "himalaya"
            "meme-maker"
            "mcporter"
            "model-usage"
            "nano-pdf"
            "node-inspect-debugger"
            "notion"
            "obsidian"
            "openai-whisper"
            "openai-whisper-api"
            "openhue"
            "oracle"
            "ordercli"
            "peekaboo"
            "sag"
            "sherpa-onnx-tts"
            "songsee"
            "sonoscli"
            "spotify-player"
            "taskflow"
            "taskflow-inbox-triage"
            "things-mac"
            "trello"
            "xurl"
          ]
        );
      };

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
        allow = [
          "memory-lancedb"
          "active-memory"
          "anthropic"
        ];

        slots = {
          contextEngine = "lossless-claw";
          memory = "memory-lancedb";
        };

        entries = {
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
                "vllm/${cfg.llmModel}"
                "zai/glm-5.3-flash"
              ];
            };
            #subagent = {
            #allowModelOverride = true;
            #allowedModels = [
            #"openrouter/xiaomi/mimo-v2.6-flash"
            #];
            #};
            config = {
              maxAssemblyTokenBudget = 100000;
              freshTailMaxTokens = 24000;
              summaryMaxCallsPerWindow = 48;
              # claude-cli host lacks assemble/compact; capture-only lowers requirement to bootstrap/after-turn/maintain
              hostFallbackMode = "capture-only";
              summaryModel = "zai/glm-5.3-flash";
              cacheAwareCompaction.enabled = true;
              ignoreSessionPatterns = [
                "agent:*:cron:**"
                "agent:*:**:active-memory:**"
                "agent:*:dreaming-narrative-**"
              ];
            };
          };

          "memory-lancedb" = {
            enabled = true;
            hooks.allowConversationAccess = true;
            config.embedding = {
              provider = "ollama";
              model = cfg.embeddingModel;
              baseUrl = "http://localhost:11434";
              dimensions = 1024;
            };
          };

          "active-memory" = {
            enabled = true;
            config = {
              mode = "escalate";
              model = "zai/glm-5.3-flash";
              agents = [ "coordinator" ];
              logging = true;
            };
          };

        }

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
            "xai"
          ]
        );
      };

      memory.search = {
        rememberAcrossConversations = false;
        provider = "openai-compatible";
        model = cfg.embeddingModel;
        remote = {
          baseUrl = "http://127.0.0.1:11434/v1";
        };
      };

      proxy = {
        proxyUrl = "http://127.0.0.1:${toString cfg.openclaw.singboxPort}";
      };

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
    "d /var/tmp/openclaw 0700 - - -"
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
