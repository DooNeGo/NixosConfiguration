(import ../ports.nix)
// {
  llmModel =
    #"orcarouter/Qwen3.8-27B-Uncensored-NVFP4";
    #"unsloth/Qwen3.8-27B-NVFP4";
    #"nvidia/Qwen3.8-27B-NVFP4";
    "unsloth/Qwen3.8-27B-NVFP4";
  #"unsloth/gemma-4-31B-it-NVFP4";

  embeddingModel =
    #"Qwen/Qwen3-Embedding-0.6B";
    #"BAAI/bge-m3";
    "qwen3-embedding:0.6b";
}
