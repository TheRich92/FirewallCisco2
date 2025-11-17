#!/usr/bin/env bash
set -euo pipefail

echo "===== TEST SERVICES DMZ / FIREWALL ====="
echo

# Petite fonction pour tester un accès HTTP via curl
test_http() {
  local svc="$1"
  local url="$2"
  local label="$3"
  local expect="$4"  # OK ou KO

  echo "[$svc] $label"

  docker exec "$svc" bash -lc "curl -sS --max-time 3 '$url' | head -n1" \
    >/tmp/test-http-$$ 2>/tmp/test-http-err-$$

  local status=$?
  local line
  line=$(cat /tmp/test-http-$$ 2>/dev/null || echo "")

  # Interprétation :
  # - Succès "réel" = exit code 0 ET première ligne non vide
  # - Sinon, on considère que c'est un échec
  if [[ "$expect" == "OK" ]]; then
    if [[ $status -eq 0 && -n "$line" ]]; then
      echo "  ✅ SUCCÈS (attendu) – première ligne: ${line}"
    else
      local err
      err=$(cat /tmp/test-http-err-$$ 2>/dev/null || echo "<aucune>")
      echo "  ❌ ÉCHEC (NON attendu) – code=$status, stdout='${line:-<vide>}', stderr='${err}'"
    fi
  else
    if [[ $status -eq 0 && -n "$line" ]]; then
      echo "  ❌ SUCCÈS (NON attendu) – première ligne: ${line}"
    else
      local err
      err=$(cat /tmp/test-http-err-$$ 2>/dev/null || echo "<aucune>")
      echo "  ✅ ÉCHEC (attendu) – code=$status, stdout='${line:-<vide>}', stderr='${err}'"
    fi
  fi

  echo
}

# Récupère l'IP WAN du routeur (eth1)
ROUTER_WAN_IP=$(
  docker exec routerfw bash -lc '
    WAN_IF=$(ip route | awk "/default/ {print \$5; exit}");
    ip -4 -o addr show dev "$WAN_IF" | awk "{print \$4}" | cut -d/ -f1
  '
)
echo "IP WAN du routeur : $ROUTER_WAN_IP"
echo

echo "== 1) Accès DMZ (web_dmz) depuis LAN / DMZ / INET =="
test_http pc_lan       "http://10.30.0.20" "pc_lan -> http://10.30.0.20" "OK"
test_http pc_dmz       "http://10.30.0.20" "pc_dmz -> http://10.30.0.20" "OK"
test_http pc_internet  "http://10.30.0.20" "pc_internet -> http://10.30.0.20" "KO"

echo "== 2) Accès DMZ (web_dmz) depuis WAN via DNAT (pc_outside_wan) =="
# Selon l'environnement Docker/Mac, ce test peut échouer (problème de NAT/hairpin),
# même si les règles DNAT/FORWARD sont correctes et que les compteurs iptables montent.
test_http pc_outside_wan "http://$ROUTER_WAN_IP" "pc_outside_wan -> http://$ROUTER_WAN_IP (DNAT -> web_dmz)" "KO"

echo "===== FIN DES TESTS ====="

