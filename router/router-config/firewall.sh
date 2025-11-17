#!/usr/bin/env bash
set -euo pipefail
echo "[firewall] === AUTO-DETECTION DES INTERFACES ==="

LAN_NET="10.20.0.0/24"
DMZ_NET="10.30.0.0/24"
INET_NET="10.10.0.0/24"
WAN_NET="172.18.0.0/16"
WAN_GW="172.18.0.1"

# -----------------------------
# AUTO-DETECTION DES INTERFACES
# -----------------------------
detect_if_prefix() {
  local prefix="$1"   # ex: "10.20.0."
  ip -4 -o addr show | awk -v P="$prefix" '{
    # $4 = "10.20.0.254/24"
    split($4, a, "/");
    ip=a[1];
    if (index(ip, P) == 1) {
      print $2;
      exit;
    }
  }'
}

IF_LAN=$(detect_if_prefix "10.20.0.")
IF_DMZ=$(detect_if_prefix "10.30.0.")
IF_INET=$(detect_if_prefix "10.10.0.")
IF_WAN=$(detect_if_prefix "172.18.0.")

echo "[firewall] IF_LAN  = $IF_LAN  ($LAN_NET)"
echo "[firewall] IF_DMZ  = $IF_DMZ  ($DMZ_NET)"
echo "[firewall] IF_INET = $IF_INET ($INET_NET)"
echo "[firewall] IF_WAN  = $IF_WAN  ($WAN_NET)"

# -----------------------------
# RESET
# -----------------------------
iptables -F
iptables -X
iptables -t nat -F

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# -----------------------------
# INPUT
# -----------------------------
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

for NET in "$LAN_NET" "$DMZ_NET" "$INET_NET"; do
  iptables -A INPUT -p icmp -s "$NET" -m limit --limit 5/sec --limit-burst 20 -j ACCEPT
done

iptables -A INPUT -i "$IF_LAN" -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

# -----------------------------
# NAT sortant WAN
# -----------------------------
iptables -t nat -A POSTROUTING -o "$IF_WAN" -j MASQUERADE

# -----------------------------
# FORWARD
# -----------------------------
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Anti-spoof
iptables -A FORWARD -i "$IF_LAN"  ! -s "$LAN_NET"  -j DROP
iptables -A FORWARD -i "$IF_DMZ"  ! -s "$DMZ_NET"  -j DROP
iptables -A FORWARD -i "$IF_INET" ! -s "$INET_NET" -j DROP

# ICMP inter-segments bloqué
iptables -A FORWARD -p icmp -i "$IF_LAN"  -o "$IF_DMZ" -j DROP
iptables -A FORWARD -p icmp -i "$IF_DMZ"  -o "$IF_LAN" -j DROP
iptables -A FORWARD -p icmp -i "$IF_LAN"  -o "$IF_INET" -j DROP
iptables -A FORWARD -p icmp -i "$IF_INET" -o "$IF_LAN" -j DROP
iptables -A FORWARD -p icmp -i "$IF_DMZ"  -o "$IF_INET" -j DROP
iptables -A FORWARD -p icmp -i "$IF_INET" -o "$IF_DMZ" -j DROP

# LAN -> WAN
iptables -A FORWARD -i "$IF_LAN" -o "$IF_WAN" -s "$LAN_NET" -m conntrack --ctstate NEW -j ACCEPT

# LAN -> DMZ (HTTP/HTTPS)
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" -s "$LAN_NET" -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT

# LAN -> ssh_dmz (port 22)
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" \
  -s "$LAN_NET" -d 10.30.0.60 -p tcp --dport 22 \
  -m conntrack --ctstate NEW -j ACCEPT


# LAN -> ftp_dmz (port 21)
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" -s "$LAN_NET" -d 10.30.0.50 -p tcp --dport 21 -m conntrack --ctstate NEW -j ACCEPT

# DMZ -> WAN (DNS + HTTP/HTTPS + ICMP)
iptables -A FORWARD -i "$IF_DMZ" -o "$IF_WAN" -s "$DMZ_NET" -p udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$IF_DMZ" -o "$IF_WAN" -s "$DMZ_NET" -p tcp -m multiport --dports 53,80,443 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$IF_DMZ" -o "$IF_WAN" -s "$DMZ_NET" -p icmp -m conntrack --ctstate NEW -j ACCEPT

# INET -> DMZ (HTTP) BLOQUÉ
iptables -A FORWARD -i "$IF_INET" -o "$IF_DMZ" -s "$INET_NET" -d "$DMZ_NET" -p tcp --dport 80 -j DROP

# -----------------------------
# DNAT WAN:80 -> web_dmz
# -----------------------------
iptables -t nat -A PREROUTING -i "$IF_WAN" -p tcp --dport 80 -j DNAT --to-destination 10.30.0.20:80
iptables -A FORWARD -i "$IF_WAN" -o "$IF_DMZ" -p tcp -d 10.30.0.20 --dport 80 -m conntrack --ctstate NEW -j ACCEPT

# -----------------------------
# Default route via WAN
# -----------------------------
ip route del default 2>/dev/null || true
ip route add default via "$WAN_GW" dev "$IF_WAN" 2>/dev/null || true

echo "[firewall] Firewall chargé."

