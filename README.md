# bonsai_docker

Runs [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)
locally with [Ollama](https://ollama.com) in Docker.

**Target machine:** a laptop running Omarchy (Arch Linux) with an NVIDIA Quadro T1000
(4 GB VRAM, Turing) and 48 GB RAM.

## 1. Prepare the laptop (once)

Omarchy usually installs the NVIDIA driver during setup. Docker also needs NVIDIA's
container toolkit to pass the GPU into containers:

```bash
nvidia-smi                                   # should list the Quadro T1000; if not: sudo pacman -S nvidia-open, then reboot
sudo pacman -S --needed docker docker-compose nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl enable --now docker && sudo systemctl restart docker
sudo usermod -aG docker "$USER"              # then log out and back in
```

Copy this folder to the laptop, then run the preflight check:

```bash
./scripts/check_host.sh
```

It checks the driver, GPU access from containers, RAM, and free disk space (about 20 GB
needed at peak).

## 2. Start it

```bash
docker compose up -d                 # first run downloads the model (~7.6 GB), so this waits a while
docker compose logs model-init       # should end with a list containing "bonsai:latest"
./scripts/smoke_test.sh              # known-answer test + speed + how much runs on the GPU
```

To watch the download from a second terminal, run `docker compose logs -f model-download`.

What `up` runs:

1. `ollama`: the server, which keeps running and has GPU access through `compose.override.yaml`.
2. `model-download`: a one-shot job that fetches `Ternary-Bonsai-2-27B-Q2_0.gguf` from Hugging Face
   and checks its sha256.
3. `model-init`: a one-shot job that imports the file once as `bonsai-base`, deletes the downloaded
   copy, then builds `bonsai` from `bonsai-base` plus the settings in `Modelfile`.

On later runs, steps 2 and 3 take seconds.

**No working GPU?** Run CPU-only with `docker compose -f compose.yaml up -d`. That skips the
GPU override file.

## 3. Use it

```bash
docker exec -it bonsai-ollama ollama run bonsai
```

The API is at `http://127.0.0.1:11434`. It speaks the native Ollama API and the
OpenAI-compatible `/v1` API, so Open WebUI, Continue, or any OpenAI client works.
Use `bonsai` as the model name.

```bash
curl http://127.0.0.1:11434/api/chat -d '{"model":"bonsai","stream":false,
  "messages":[{"role":"user","content":"Hello!"}]}'
```

Check where the model is running: `docker exec bonsai-ollama ollama ps`. The PROCESSOR column
shows the CPU/GPU split.

Stop the stack with `docker compose down`. Add `-v` to also delete the downloaded weights.

## What to expect on this hardware

- **The 7.6 GB model doesn't fit in 4 GB of VRAM.** Ollama automatically puts as many layers
  as fit on the T1000 (very roughly a third of the model) and runs the rest on the CPU from
  the 48 GB of RAM. That works, but the CPU part sets the pace.
- **Speed (estimate, not measured):** probably a few tokens per second. RAM bandwidth limits
  how fast a 27B model generates, and partial offload helps only modestly. The smoke test
  prints the real number. Please check it.
- **It thinks first.** This is a reasoning model, so it writes hidden "thinking" before every
  answer, which multiplies the wait. For quick answers, turn it off per request with
  `"think": false`, or with `/set nothink` in `ollama run`.
- **Context is 32K tokens** (`num_ctx` in `Modelfile`). With 48 GB RAM you can raise it to
  64K or 128K. The KV cache costs about 2 GB per 32K tokens, and a bigger context leaves
  less of the 4 GB VRAM for model layers.

## Why it's set up this way

- **The model file is `Q2_0`, not `PQ2_0` or `PTQ1_0`.** Those two are Prism's own
  quantization types. Ollama can't load them yet
  ([ollama#18521](https://github.com/ollama/ollama/issues/18521)). `Q2_0` holds the same
  ternary weights in a standard llama.cpp type.
- **The file is downloaded by URL, not with `ollama pull hf.co/...:Q2_0`.** That tag also matches
  `PQ2_0` (it ends in "Q2_0"), and Ollama picks the PQ2_0 file. Building the model then fails with
  `unsupported tensor "output.weight" size overflows`. This was confirmed on 2026-11-17: the
  downloaded blob had the PQ2_0 file's sha256 and tensor type 142.
- **Ollama is pinned to `0.40.16`.** `Q2_0` needs llama.cpp b11556 or newer, and this
  Ollama release bundles b12177. Older builds load the file without any error and then
  produce garbled output (see the model's `KNOWN_ISSUES.md`). The smoke test checks for
  that failure with a known-answer prompt.
  Re-run the smoke test whenever you bump the image tag.
- **The port is bound to localhost.** To expose it on your network, change the port
  mapping in `compose.yaml`.

## Settings

| Setting | Where | Default |
|---|---|---|
| Host port | `OLLAMA_PORT` env / `.env` | `11434` |
| Idle unload time | `OLLAMA_KEEP_ALIVE` | `30m` |
| Context length, sampling | `Modelfile` (then `docker compose up model-init`; no re-download) | 32768, model-card values |
| GPU on/off | `compose.override.yaml` (CPU-only: `-f compose.yaml`) | GPU on |

## License

The configuration in this repository is MIT licensed (`LICENSE`). The model weights are
Apache-2.0, from PrismML. Ollama is MIT.

---

*AI involvement in this project is declared in
[aidecl.yaml](./aidecl.yaml) following the
[AI Declaration Format](https://ai-declaration.org).*
