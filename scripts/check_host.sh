#!/usr/bin/env bash
# Preflight for the target laptop: checks the NVIDIA driver, Docker GPU
# access, RAM and disk before the first `docker compose up`.
# Usage: ./scripts/check_host.sh
set -uo pipefail

ok=1
pass() { echo "  ok    $*"; }
warn() { echo "  WARN  $*"; }
bad()  { echo "  FAIL  $*"; ok=0; }

echo "NVIDIA driver"
if nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader >/dev/null 2>&1; then
  pass "$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
else
  bad "nvidia-smi failed: the driver is not installed or loaded (Arch: nvidia-open, then reboot)"
fi

echo "Docker"
if docker info >/dev/null 2>&1; then pass "daemon reachable"; else bad "docker not running or no permission (add user to 'docker' group)"; fi
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia \
   || command -v nvidia-ctk >/dev/null 2>&1; then
  pass "nvidia-container-toolkit present"
else
  bad "nvidia-container-toolkit missing (sudo pacman -S nvidia-container-toolkit)"
fi
if docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L >/dev/null 2>&1; then
  pass "containers can see the GPU"
else
  bad "containers can't see the GPU (sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker)"
fi

echo "Memory and disk"
mem_gb=$(awk '/MemTotal/ { printf "%d", $2/1024/1024 }' /proc/meminfo)
[ "$mem_gb" -ge 16 ] && pass "RAM ${mem_gb} GB" || warn "RAM ${mem_gb} GB: the model needs ~8 GB plus the KV cache"
disk_gb=$(df -BG --output=avail "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /)" | tail -1 | tr -dc 0-9)
[ "${disk_gb:-0}" -ge 20 ] && pass "disk ${disk_gb} GB free for Docker" \
  || bad "disk ${disk_gb:-?} GB free: need ~20 GB (16 GB peak during import, 8 GB afterwards)"

[ "$ok" = 1 ] && echo "Ready: docker compose up -d" || { echo "Fix the FAIL items first."; exit 1; }
