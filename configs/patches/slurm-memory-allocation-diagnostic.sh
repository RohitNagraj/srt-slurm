#!/usr/bin/env bash

# This setup hook intentionally exits before vLLM starts. It is used only by
# short allocation diagnostics that compare Slurm and cgroup memory policy.
set +e

section() {
  printf '\n===== %s =====\n' "$1"
}

read_if_present() {
  local path="$1"
  if [[ -r "$path" ]]; then
    printf '%s:\n' "$path"
    cat "$path"
  fi
}

section "identity"
date -u
hostname -f
id
printf 'SLURM_JOB_ID=%s\n' "${SLURM_JOB_ID:-}"
printf 'SLURM_JOB_NAME=%s\n' "${SLURM_JOB_NAME:-}"
printf 'SLURM_JOB_NODELIST=%s\n' "${SLURM_JOB_NODELIST:-}"
printf 'SLURM_JOB_NUM_NODES=%s\n' "${SLURM_JOB_NUM_NODES:-}"
printf 'SLURM_CPUS_ON_NODE=%s\n' "${SLURM_CPUS_ON_NODE:-}"
printf 'SLURM_MEM_PER_NODE=%s\n' "${SLURM_MEM_PER_NODE:-}"
printf 'SLURM_MEM_PER_CPU=%s\n' "${SLURM_MEM_PER_CPU:-}"

section "slurm job"
if command -v scontrol >/dev/null 2>&1 && [[ -n "${SLURM_JOB_ID:-}" ]]; then
  scontrol show job -dd "$SLURM_JOB_ID"
else
  echo "scontrol unavailable inside worker container"
fi

section "slurm accounting"
if command -v sstat >/dev/null 2>&1 && [[ -n "${SLURM_JOB_ID:-}" ]]; then
  sstat -j "${SLURM_JOB_ID}.batch" \
    --format=JobID,MaxRSS,AveRSS,MaxVMSize,AveVMSize -P
else
  echo "sstat unavailable inside worker container"
fi

section "host memory"
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Unevictable|Mlocked|Shmem):' \
  /proc/meminfo
free -b || true

section "cgroup membership"
cat /proc/self/cgroup
printf '\nPID 1 cgroup:\n'
cat /proc/1/cgroup

section "cgroup v2 limits"
self_cgroup="$(awk -F: '$1 == "0" {print $3}' /proc/self/cgroup)"
cgroup_path="/sys/fs/cgroup${self_cgroup:-/}"
while [[ "$cgroup_path" == /sys/fs/cgroup* ]]; do
  printf '\n-- %s --\n' "$cgroup_path"
  for metric in \
    memory.current memory.max memory.high memory.low memory.min memory.peak \
    memory.events memory.events.local memory.swap.current memory.swap.max \
    cpuset.cpus.effective cpuset.mems.effective pids.current pids.max; do
    read_if_present "$cgroup_path/$metric"
  done
  [[ "$cgroup_path" == "/sys/fs/cgroup" ]] && break
  cgroup_path="${cgroup_path%/*}"
done

section "process limits"
ulimit -a
cat /proc/self/limits
grep -E '^(Cpus_allowed_list|Mems_allowed_list):' /proc/self/status

section "numa"
if command -v numactl >/dev/null 2>&1; then
  numactl --hardware
else
  echo "numactl unavailable inside worker container"
fi
lscpu || true

section "shared memory"
df -B1 /dev/shm || true
mount | grep -E '(/dev/shm|cgroup)' || true

section "diagnostic complete"
echo "Intentional pre-model exit: no model weights or KV pool were allocated."
exit 86
