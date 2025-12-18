#!/usr/bin/env bash
set -euo pipefail

echo "[firewall] === APPLICATION DES RÈGLES ==="

# --- 1. DEFINITIONS ---
LAN_NET="10.20.0.0/24"
DMZ_NET="10.30.0.0/24"
INET_NET="10.10.0.0/24"

WEB_DMZ_IP="10.30.0.20"
FTP_DMZ_IP="10.30.0.50"
SSH_DMZ_IP="10.30.0.60"

# Import variables d'environnement (si script lancé manuellement pour test)
IF_LAN="${IF_LAN:-}"
IF_DMZ="${IF_DMZ:-}"
IF_INET="${IF_INET:-}"
IF_WAN="${IF_WAN:-}"

# --- 2. RESET ---
iptables -F
iptables -t nat -F
iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# --- 3. INPUT (Accès au Routeur lui-même) ---
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ICMP (Ping) autorisé depuis l'interne pour diag
for NET in "$LAN_NET" "$DMZ_NET" "$INET_NET"; do
  iptables -A INPUT -p icmp -s "$NET" -m limit --limit 5/s -j ACCEPT
done

# SSH Admin (Seulement depuis LAN)
iptables -A INPUT -i "$IF_LAN" -p tcp --dport 22 -s "$LAN_NET" -j ACCEPT

# SNMP (Monitoring Zabbix depuis LAN)
iptables -A INPUT -i "$IF_LAN" -p udp --dport 161 -s "$LAN_NET" -j ACCEPT


# --- 4. NAT (Sortie Internet) ---
iptables -t nat -A POSTROUTING -o "$IF_WAN" -j MASQUERADE


# --- 5. FORWARD (Transit) ---
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Anti-Spoofing basique
iptables -A FORWARD -i "$IF_LAN"  ! -s "$LAN_NET"  -j DROP
iptables -A FORWARD -i "$IF_DMZ"  ! -s "$DMZ_NET"  -j DROP
iptables -A FORWARD -i "$IF_INET" ! -s "$INET_NET" -j DROP

# >>> LAN VERS EXTERIEUR <<<
# Accès Internet
iptables -A FORWARD -i "$IF_LAN" -o "$IF_WAN" -s "$LAN_NET" -j ACCEPT

# Accès Services DMZ (Web, SSH, FTP)
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" -p tcp -m multiport --dports 80,443,22 -j ACCEPT
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" -p tcp -m multiport --dports 21,21000:21010 -j ACCEPT

# Accès SNMP (LAN -> DMZ pour monitorer les serveurs)
iptables -A FORWARD -i "$IF_LAN" -o "$IF_DMZ" -p udp --dport 161 -j ACCEPT


# >>> DMZ VERS EXTERIEUR <<<
# Mises à jour / DNS (Limité)
iptables -A FORWARD -i "$IF_DMZ" -o "$IF_WAN" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$IF_DMZ" -o "$IF_WAN" -p tcp -m multiport --dports 80,443,53 -j ACCEPT


# >>> INTERNET (Hacker) VERS DMZ <<<
# Web (HTTP/HTTPS) autorisé
iptables -A FORWARD -i "$IF_INET" -o "$IF_DMZ" -p tcp -m multiport --dports 80,443 -j ACCEPT

# FTP autorisé (Port 21 + Plage passive)
iptables -A FORWARD -i "$IF_INET" -o "$IF_DMZ" -d "$FTP_DMZ_IP" -p tcp -m multiport --dports 21,21000:21010 -j ACCEPT


# --- 6. LOGGING & DROP (Pour le Rapport) ---
# Logguer tout ce qui va être bloqué (Utile pour prouver les attaques)
iptables -A FORWARD -m limit --limit 10/min -j LOG --log-prefix "FW_DROP_FWD: " --log-level 4
iptables -A INPUT   -m limit --limit 10/min -j LOG --log-prefix "FW_DROP_IN: "  --log-level 4

# Drop explicite (redondant avec la Policy mais plus sûr)
iptables -A FORWARD -j DROP
iptables -A INPUT   -j DROP

echo "[firewall] Règles appliquées avec succès."