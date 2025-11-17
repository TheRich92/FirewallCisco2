#!/usr/bin/env bash
set -euo pipefail

ok() { echo "✅ $*"; }
ko() { echo "❌ $*"; }

run_ping() {
  local svc="$1" target="$2" expect="$3"
  if docker exec "$svc" bash -lc "ping -c1 -W1 $target >/dev/null 2>&1"; then
    [[ "$expect" == "OK" ]] && ok "$svc -> $target : OK (attendu)" || ko "$svc -> $target : OK (NON attendu)"
  else
    [[ "$expect" == "KO" ]] && ok "$svc -> $target : BLOQUÉ (attendu)" || ko "$svc -> $target : BLOQUÉ (NON attendu)"
  fi
}

echo "== INPUT diag =="
run_ping pc_lan      10.20.0.254 OK
run_ping pc_dmz      10.30.0.254 OK
run_ping pc_internet 10.10.0.254 OK

echo
echo "== Inter-segments (doivent être BLOQUÉS) =="
run_ping pc_lan      10.30.0.10 KO
run_ping pc_lan      10.10.0.10 KO
run_ping pc_dmz      10.20.0.10 KO
run_ping pc_dmz      10.10.0.10 KO
run_ping pc_internet 10.20.0.10 KO
run_ping pc_internet 10.30.0.10 KO

echo
echo "== Internet (autorisé LAN & DMZ) =="
run_ping pc_lan 1.1.1.1 OK
run_ping pc_dmz 1.1.1.1 OK

echo
echo "== Internet depuis INET (bloqué par design) =="
run_ping pc_internet 1.1.1.1 KO

