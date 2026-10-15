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

  home.packages = with pkgs; [ ffmpeg ];

  programs.openclaw = {
    enable = true;

    runtimePlugins = [
      "searxng"
      "lossless-claw"
      "memory-lancedb"
      #"tokenjuice"
      "codex"
      "zai"
    ];

    bundledPlugins = {
      summarize.enable = false;
      goplaces.enable = false;
    };

    environment = {
      OPENROUTER_API_KEY = "${config.home.homeDirectory}/.secrets/openclaw-openrouter-api-key";
      ZAI_API_KEY = "${config.home.homeDirectory}/.secrets/zai-api-key";
      # temporary: cache tracing for the native-runtime cache investigation (T52); contains full prompts, remove after diagnosis
      #OPENCLAW_CACHE_TRACE = "1";
      #OPENCLAW_CACHE_TRACE_FILE = "${config.home.homeDirectory}/.openclaw/logs/cache-trace.jsonl";
      #OPENCLAW_CACHE_TRACE_MESSAGES = "1";
      #OPENCLAW_CACHE_TRACE_PROMPT = "1";
      #OPENCLAW_CACHE_TRACE_SYSTEM = "1";
    };

    skills = [
      {
        name = "skill-vetter";
        description = "Security-first skill vetting for AI agents. Use before installing any skill from ClawdHub, GitHub, or other sources. Checks for red flags, permission scope, and suspicious patterns.";
        mode = "symlink";
        source = toString ./skills/skill-vetter;
      }
    ];

    workspace.files =
      let
        personaAgents = [
          "coordinator"
          "coder"
          "researcher"
          "reviewer"
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
            lib.filter (
              file: builtins.pathExists (./openclaw-local/workspace + "/${agent}/${file}")
            ) personaFiles
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

      commands.ownerAllowFrom = [ "telegram:760128577" ];

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
          baseUrl = "http://100.114.127.10:8000/v1";
          apiKey = "EMPTY";
          timeoutSeconds = 900;
        };

        zai.baseUrl = "https://api.z.ai/api/coding/paas/v4";
      };

      #messages.responseUsage = "full";

      agents = {
        ownership = "explicit";

        defaults = {
          model = {
            primary =
              "anthropic/claude-haiku-5-5";
              #"zai/glm-5.3-flashx";
            fallbacks = [
              "zai/glm-5.3-flashx"
              "zai/glm-5.3-flash"
              #"anthropic/claude-haiku-5-5"
              "vllm/${cfg.llmModel}"
              #"zai/glm-5.3-flashx"
              #"openrouter/free"
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
              "vllm/${cfg.llmModel}".params.thinking = "low";
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

          utilityModel =
            "anthropic/claude-haiku-5-5";
            #"zai/glm-5.3-flash";

          heartbeat = {
            model =
              "anthropic/claude-haiku-5-5";
              #"zai/glm-5.3-flash";
            isolatedSession = true;
            lightContext = true;
            every = "0m";
          };

          # Ambient owners (systemAgent, heartbeat) fall back to this path;
          # without it they land in the shared root ~/.openclaw/workspace.
          workspace = "~/.openclaw/workspace/coordinator";

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
            identity = {
              name = "Claw";
              emoji = "🦞";
            };

            workspace = "~/.openclaw/workspace/coordinator";

            subagents = {
              delegationMode = "prefer";
              allowAgents = [
                "researcher"
                "coder"
                "reviewer"
                "advisor"
              ];
            };

            tools.codeMode = "auto";

            models = {
              "zai/glm-5.3".params.thinking = "high";
              "vllm/${cfg.llmModel}".params.thinking = "medium";
            };

            model = {
              primary =
                #"openai/gpt-6.1-sol";
                "anthropic/claude-sonnet-5-5";
                #"zai/glm-5.3";
              fallbacks = [
                "anthropic/claude-sonnet-5-5"
                "zai/glm-5.3"
                "vllm/${cfg.llmModel}"
                #"openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "openai/gpt-6.1-sol"
              "anthropic/claude-sonnet-5-5"
              "zai/glm-5.3"
              "vllm/${cfg.llmModel}"
              "openrouter/free"
            ];
          };

          researcher = {
            identity = {
              name = "Scuttle";
              emoji = "🦐";
            };

            workspace = "~/.openclaw/workspace/researcher";

            tools.deny = [
              "message"
              "sessions_spawn"
            ];

            tools.codeMode = "auto";

            modelPolicy.allow = [
              "anthropic/claude-haiku-5-5"
              "zai/glm-5.3-flash"
              "zai/glm-5.3-flashx"
              "openrouter/free"
              "vllm/${cfg.llmModel}"
            ];
          };

          coder = {
            identity = {
              name = "Pinch";
              emoji = "🦀";
            };

            workspace = "~/.openclaw/workspace/coder";

            modelPolicy.allow = [
              "anthropic/claude-haiku-5-5"
              "zai/glm-5.3-flash"
              "zai/glm-5.3-flashx"
              "openrouter/free"
              "vllm/${cfg.llmModel}"
            ];

            tools.codeMode = "auto";
          };

          advisor = {
            identity = {
              name = "Sage";
              emoji = "🧠";
            };

            workspace = "~/.openclaw/workspace/advisor";

            tools.allow = [
              "read"
              "skill_workshop"
            ];

            tools.codeMode = "auto";

            models."zai/glm-5.3".params.thinking = "max";
            models."vllm/${cfg.llmModel}".params.thinking = "xhigh";

            model = {
              primary =
                "anthropic/claude-opus-5-5";
                #"zai/glm-5.3";
              fallbacks = [
                "zai/glm-5.3"
                "vllm/${cfg.llmModel}"
                #"openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-opus-5-5"
              "zai/glm-5.3"
              "openrouter/free"
              "vllm/${cfg.llmModel}"
            ];
          };

          reviewer = {
            identity = {
              name = "Gauge";
              emoji = "🔍";
            };

            workspace = "~/.openclaw/workspace/reviewer";

            tools.deny = [
              "browser"
              "message"
              "sessions_spawn"
            ];

            tools.codeMode = "auto";

            models."zai/glm-5.3".params.thinking = "high";
            models."vllm/${cfg.llmModel}".params.thinking = "medium";

            model = {
              primary =
                "anthropic/claude-sonnet-5-5";
                #"zai/glm-5.3";
              fallbacks = [
                "vllm/${cfg.llmModel}"
                "zai/glm-5.3"
                #"openrouter/free"
              ];
            };

            modelPolicy.allow = [
              "anthropic/claude-sonnet-5-5"
              "zai/glm-5.3"
              "openrouter/free"
              "vllm/${cfg.llmModel}"
            ];
          };
        };
      };

      talk.agentId = "coordinator";

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
          "browser"
          "telegram"
          "device-pair"
          "codex"
        ];

        slots = {
          contextEngine = "lossless-claw";
          memory = "memory-lancedb";
        };

        entries = {
          telegram.enabled = true;
          codex.enabled = true;

          "device-pair".config.publicUrl = "https://openclaw-webui.tail416d29.ts.net";

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
                "anthropic/claude-haiku-5-5"
                "zai/glm-5.3-flash"
                "zai/glm-5.3-flashx"
                "vllm/${cfg.llmModel}"
              ];
            };
            config = {
              maxAssemblyTokenBudget = 130000;
              freshTailMaxTokens = 20000;
              # claude-cli host lacks assemble/compact; capture-only lowers requirement to bootstrap/after-turn/maintain
              hostFallbackMode = "capture-only";
              summaryModel =
                "anthropic/claude-haiku-5-5";
                #"zai/glm-5.3-flash";
                #"vllm/${cfg.llmModel}";
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
            config = {
              autoRecall = false;
              embedding = {
                provider = "ollama";
                model = cfg.embeddingModel;
                baseUrl = "http://localhost:11434";
                dimensions = 1024;
              };
            };
          };

          "active-memory" = {
            enabled = true;
            config = {
              mode = "escalate";
              model =
                "anthropic/claude-haiku-5-5";
                #"zai/glm-5.3-flashx";
              modelFallback = "vllm/${cfg.llmModel}";
              agents = [ "coordinator" ];
              logging = true;
              queryMode = "recent";
              promptStyle = "balanced";
              toolsAllow = [
                "memory_recall"
                "lcm_grep"
                "lcm_describe"
                "lcm_expand_query"
              ];
              promptAppend = "Use memory_recall for long-term preferences and decisions. Use lcm_grep first for compacted conversation recall, lcm_describe for a specific summary, lcm_expand_query only when exact details may have been compacted away. Return NONE if nothing is clearly useful.";
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
        rememberAcrossConversations = true;
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
        enabled = true;
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
  # - TimeoutStopSec 330s: gateway drains up to 300s (docs/gateway/index.md);
  # - TMPDIR: the gateway snapshots plugins (~380 MB each) under os.tmpdir(),
  #   which is tmpfs /tmp by default; point it at /var/tmp/openclaw instead;
  # - failed starts leak openclaw-plugin-build-* dirs, so ExecStartPre clears
  #   both the old /tmp ones and the new location (failure ignored via "-").
  #   Manual cleanup: stop the unit first; deleting them while the gateway
  #   runs breaks plugin loading (MODULE_NOT_FOUND for subagents);
  # - crash-loop cap: 10s between starts, at most 5 starts per 300s. After
  #   that the unit stays failed until `systemctl --user reset-failed`.
  systemd.user.services."openclaw-gateway" = {
    Unit = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Environment = [ "TMPDIR=/var/tmp/openclaw" ];
      ExecStartPre = [
        "-${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/rm -rf /tmp/openclaw-plugin-build-* /var/tmp/openclaw/openclaw-plugin-build-*'"
      ];
      RestartSec = lib.mkForce "10s";
      TimeoutStopSec = "330";
    };
  };
}
