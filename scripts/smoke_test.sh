#!/usr/bin/env bash
# Smoke test: checks that the server is up, the "bonsai" model is
# registered, and a known-answer prompt comes back with the right answer.
# Usage: ./scripts/smoke_test.sh   (OLLAMA_URL overrides the endpoint)
set -euo pipefail

URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
MODEL="${MODEL:-bonsai}"

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "1/3 server reachable at $URL"
ver=$(curl -fsS "$URL/api/version") || fail "Ollama is not responding. Run: docker compose up -d"
echo "    $ver"

echo "2/3 model '$MODEL' registered"
curl -fsS "$URL/api/tags" | grep -q "\"$MODEL:latest\"" \
  || fail "model not found. Check: docker compose logs model-init"

echo "3/3 known-answer prompt (the first CPU load takes a while)"
# Thinking is turned off so the answer stays short and the test runs fast.
resp=$(curl -fsS --max-time 900 "$URL/api/chat" -d "{
  \"model\": \"$MODEL\",
  \"stream\": false,
  \"think\": false,
  \"options\": {\"temperature\": 0, \"num_predict\": 32},
  \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France? Answer with one word.\"}]
}") || fail "chat request failed"

# JSON string value of "content", escaped quotes allowed (no jq/python needed).
answer=$(printf '%s' "$resp" | sed -nE 's/.*"content":"(([^"\\]|\\.)*)".*/\1/p' | head -1)
echo "    answer: $answer"
printf '%s' "$answer" | grep -qi 'paris' \
  || fail "expected 'Paris'. A garbled answer usually means the bundled llama.cpp is too old for Q2_0"

tps=$(printf '%s' "$resp" | sed -n 's/.*"eval_count":\([0-9]*\).*"eval_duration":\([0-9]*\).*/\1 \2/p' \
  | awk '{ if ($2>0) printf "%.2f", $1/($2/1e9) }')
echo "    generation speed: ${tps:-?} tokens/s"

# How much of the loaded model sits in VRAM (0 = running on CPU only).
read -r size vram < <(curl -fsS "$URL/api/ps" \
  | sed -n 's/.*"size":\([0-9]*\).*"size_vram":\([0-9]*\).*/\1 \2/p' | head -1) || true
if [ -n "${size:-}" ] && [ "$size" -gt 0 ]; then
  awk -v s="$size" -v v="$vram" 'BEGIN { printf "    loaded: %.1f GB total, %.1f GB on GPU (%d%%)\n", s/1e9, v/1e9, 100*v/s }'
  [ "$vram" -gt 0 ] || echo "    note: no GPU offload. On the T1000 laptop, check: docker exec bonsai-ollama nvidia-smi"
fi
echo "OK"
