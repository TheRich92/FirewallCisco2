#!/usr/bin/env bash
set -euo pipefail

echo "[routerfw] === Initialisation du routeur ==="

# DNS basique pour apt/résolution (utile dans certaines config Docker Desktop)
echo "nameserver 1.1.1.1" > /etc/resolv.conf || true

# Outils réseau/iptables/sysctl
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq iproute2 iptables procps curl netcat-openbsd >/dev/null

# Activer le routage IPv4
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Helpers pour retrouver les noms d'interfaces
get_if_by_ip() { ip -4 -o addr show | awk -v IP="$1" '$4 ~ IP"/" {print $2; exit}'; }

IF_LAN="$(get_if_by_ip 10.20.0.254 || true)"
IF_DMZ="$(get_if_by_ip 10.30.0.254 || true)"
IF_INET="$(get_if_by_ip 10.10.0.254 || true)"

# L'interface WAN est "la restante" (attachée au réseau wan_net)
# On la déduit par différence (liste des interfaces avec IP v4 non-loopback)
ALL_IFS=($(ip -4 -o addr show | awk '!/ lo / {print $2}' | sort -u))
WAN_CANDIDATE=""
for i in "${ALL_IFS[@]}"; do
  if [[ "$i" != "$IF_LAN" && "$i" != "$IF_DMZ" && "$i" != "$IF_INET" ]]; then
    WAN_CANDIDATE="$i"
    break
  fi
done
IF_WAN="${WAN_CANDIDATE:-eth0}"
# Forcer la route par défaut via le WAN (utile avec Docker bridge)
WAN_GW="$(ip -4 route | awk -v IF="$IF_WAN" '$1=="default" && $0 ~ (" dev "IF" "){print $3; exit}')"
if [ -z "$WAN_GW" ]; then
  # fallback standard: .1 du sous-réseau Docker (ex: 172.18.0.1)
  WAN_GW="$(ip -4 addr show dev "$IF_WAN" | awk "/inet /{print \$4}" | awk -F'[./ ]' '{printf "%s.%s.%s.1\n",$1,$2,$3}')"
fi
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

# Charger les règles (pour l’instant : tout ouvert ; on durcira à l’Étape 2)
if [[ -x /router-config/firewall.sh ]]; then
  bash /router-config/firewall.sh || echo "[routerfw] ⚠️  Erreur firewall.sh"
else
  echo "[routerfw] ⚠️  /router-config/firewall.sh introuvable ou non exécutable"
fi

echo "[routerfw] Routeur prêt. (sleep infini)"
tail -f /dev/null

