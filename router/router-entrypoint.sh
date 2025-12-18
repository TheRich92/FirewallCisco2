#!/usr/bin/env bash
set -euo pipefail

echo "[routerfw] === Initialisation du routeur ==="

# DNS
echo "nameserver 1.1.1.1" > /etc/resolv.conf || true

# Installation des outils (Ajout de snmpd)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq iputils-ping iproute2 iptables ntpdate procps curl netcat-openbsd snmpd >/dev/null

# Activer le routage
sysctl -w net.ipv4.ip_forward=1 >/dev/null || echo "[routerfw] ⚠️ Impossible d'activer net.ipv4.ip_forward"

# Synchro NTP
ntpdate -u pool.ntp.org || echo "[routerfw] ⚠️ Impossible de synchroniser l'heure (NTP)"

# --- CONFIG SNMP (Zabbix Agent) ---
echo "[routerfw] Configuration SNMP (public)..."
# Écoute sur UDP 161, communauté 'public' en lecture seule
cat <<EOF > /etc/snmp/snmpd.conf
agentAddress udp:161
rocommunity public
EOF
service snmpd restart || echo "[routerfw] Erreur démarrage snmpd"


# --- DÉTECTION WAN AUTOMATIQUE ---
echo "[routerfw] Détection de l'interface WAN..."
IF_WAN=$(ip -4 route show default | awk '{print $5}' | head -n1)
WAN_GW=$(ip -4 route show default | awk '{print $3}' | head -n1)

if [[ -z "$IF_WAN" || -z "$WAN_GW" ]]; then
    echo "[routerfw] ❌ ERREUR CRITIQUE: WAN introuvable."
    ip route
    exit 1
fi
echo "[routerfw] WAN détecté : Interface=$IF_WAN, Gateway=$WAN_GW"


# --- IDENTIFICATION DES INTERFACES LOCALES ---
get_if_by_ip() {
  ip -4 -o addr show | awk -v IP="$1" '$4 ~ IP"/" {print $2; exit}'
}

IF_LAN="$(get_if_by_ip 10.20.0.254 || true)"
IF_DMZ="$(get_if_by_ip 10.30.0.254 || true)"
IF_INET="$(get_if_by_ip 10.10.0.254 || true)"

echo "[routerfw] Interfaces:"
echo "  LAN : $IF_LAN"
echo "  DMZ : $IF_DMZ"
echo "  INET: $IF_INET"
echo "  WAN : $IF_WAN"

export IF_LAN IF_DMZ IF_INET IF_WAN

# --- LANCEMENT FIREWALL ---
if [[ -x /router-config/firewall.sh ]]; then
  bash /router-config/firewall.sh || echo "[routerfw] ⚠️  Erreur firewall.sh"
else
  echo "[routerfw] ⚠️  /router-config/firewall.sh introuvable"
fi

echo "[routerfw] Routeur prêt."
tail -f /dev/null