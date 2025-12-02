#!/usr/bin/env bash
set -euo pipefail

echo "[routerfw] === Initialisation du routeur ==="

# DNS basique pour apt/résolution
echo "nameserver 1.1.1.1" > /etc/resolv.conf || true

# Outils réseau/iptables/sysctl
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq iputils-ping iproute2 iptables ntpdate procps curl netcat-openbsd >/dev/null

# Activer le routage IPv4
sysctl -w net.ipv4.ip_forward=1 >/dev/null || echo "[routerfw] ⚠️ Impossible d'activer net.ipv4.ip_forward"

echo "[routerfw] Synchronisation de l'heure avec NTP…"
ntpdate -u pool.ntp.org || echo "[routerfw] ⚠️ Impossible de synchroniser l'heure (NTP)"

# Helper pour retrouver une interface à partir d'une IP
get_if_by_ip() {
  ip -4 -o addr show | awk -v IP="$1" '$4 ~ IP"/" {print $2; exit}'
}

# Adapté à ton schéma d'adressage
#  - LAN   : 10.20.0.254
#  - DMZ   : 10.30.0.254
#  - INET  : 10.10.0.254
IF_LAN="$(get_if_by_ip 10.20.0.254 || true)"
IF_DMZ="$(get_if_by_ip 10.30.0.254 || true)"
IF_INET="$(get_if_by_ip 10.10.0.254 || true)"

# === WAN / Internet Docker ===
# On sait que le WAN est sur le réseau 172.18.0.0/16, interface eth3
IF_WAN="eth3"
WAN_GW="172.18.0.1"

ip route del default 2>/dev/null || true
ip route add default via "$WAN_GW" dev "$IF_WAN" || true
echo "[routerfw] Default route via $IF_WAN -> $WAN_GW"


echo "[routerfw] Interfaces détectées:"
echo "  IF_LAN = ${IF_LAN:-<inconnue>}"
echo "  IF_DMZ = ${IF_DMZ:-<inconnue>}"
echo "  IF_INET= ${IF_INET:-<inconnue>}"
echo "  IF_WAN = ${IF_WAN:-<inconnue>}"

# Variables exportées pour firewall.sh
export IF_LAN IF_DMZ IF_INET IF_WAN

# Charger les règles du firewall
if [[ -x /router-config/firewall.sh ]]; then
  bash /router-config/firewall.sh || echo "[routerfw] ⚠️  Erreur firewall.sh"
else
  echo "[routerfw] ⚠️  /router-config/firewall.sh introuvable ou non exécutable"
fi

echo "[routerfw] Routeur prêt. (sleep infini)"
tail -f /dev/null
