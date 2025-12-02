#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Firewall Étape 2 — propre & durci
#
# Topologie logique :
#   LAN_NET  = 10.20.0.0/24  (pc_lan         via IF_LAN)
#   DMZ_NET  = 10.30.0.0/24  (web_dmz, ftp_dmz, ssh_dmz, dvwa_db via IF_DMZ)
#   INET_NET = 10.10.0.0/24  (pc_internet    via IF_INET)
#   WAN      = bridge Docker vers Internet réel (pc_outside_wan) via IF_WAN
#
# Hypothèse : IF_LAN / IF_DMZ / IF_INET / IF_WAN sont déjà exportées
# par /router-entrypoint.sh. On les utilise directement ici.
# ------------------------------------------------------------------------------

set -euo pipefail

echo "[firewall] === DÉMARRAGE (Étape 2 propre) ==="

# --- Plan d’adressage ---------------------------------------------------------
LAN_NET="10.20.0.0/24"
DMZ_NET="10.30.0.0/24"
INET_NET="10.10.0.0/24"

# Hôtes DMZ importants
WEB_DMZ_IP="10.30.0.20"   # nginx DMZ
FTP_DMZ_IP="10.30.0.50"   # ftp_dmz (pyftpdlib)
SSH_DMZ_IP="10.30.0.60"   # ssh_dmz (sshd)

# Interfaces (fournies par router-entrypoint)
IF_LAN="${IF_LAN:-}"
IF_DMZ="${IF_DMZ:-}"
IF_INET="${IF_INET:-}"
IF_WAN="${IF_WAN:-}"

echo "[firewall] IF_LAN = ${IF_LAN:-<vidé>} ($LAN_NET)"
echo "[firewall] IF_DMZ = ${IF_DMZ:-<vidé>} ($DMZ_NET)"
echo "[firewall] IF_INET= ${IF_INET:-<vidé>} ($INET_NET)"
echo "[firewall] IF_WAN = ${IF_WAN:-<vidé>} (WAN)"

# Sanity check : on refuse de continuer si une interface est vide
for v in IF_LAN IF_DMZ IF_INET IF_WAN; do
  if [[ -z "${!v:-}" ]]; then
    echo "[firewall] ERREUR: variable $v vide, vérifier router-entrypoint.sh"
    exit 1
  fi
done

# --- Reset propre -------------------------------------------------------------
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Politiques par défaut
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT

# ==============================================================================
#  INPUT  (trafic à destination du routeur)
# ==============================================================================

# Loopback
iptables -A INPUT -i lo -j ACCEPT

# Connexions établies / associées
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ICMP de diag depuis les trois segments internes (vers le routeur uniquement)
for NET in "$LAN_NET" "$DMZ_NET" "$INET_NET"; do
  iptables -A INPUT -p icmp -s "$NET" -m limit --limit 5/second --limit-burst 20 -j ACCEPT
done

iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A INPUT  -p udp --sport 123 -j ACCEPT


# SSH d’admin vers le routeur depuis le LAN uniquement
iptables -A INPUT -i "$IF_LAN" -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

# (Tout le reste est DROP par policy)

# ==============================================================================
#  NAT sortant (vers Internet réel)
# ==============================================================================

# NAT sur l’interface WAN uniquement
iptables -t nat -A POSTROUTING -o "$IF_WAN" -j MASQUERADE

# ==============================================================================
#  FORWARD (transit entre segments)
# ==============================================================================

# 0) Connexions établies / associées
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- Anti-spoof : la source doit correspondre au segment de l’interface entrante
iptables -A FORWARD -i "$IF_LAN"  ! -s "$LAN_NET"  -j DROP
iptables -A FORWARD -i "$IF_DMZ"  ! -s "$DMZ_NET"  -j DROP
iptables -A FORWARD -i "$IF_INET" ! -s "$INET_NET" -j DROP
# IF_WAN -> on laisse la policy DROP gérer les flux non autorisés

# --- ICMP entre segments internes BLOQUÉ (on garde juste le diag vers le routeur)
iptables -A FORWARD -i "$IF_LAN"  -o "$IF_DMZ"  -p icmp -j DROP
iptables -A FORWARD -i "$IF_DMZ"  -o "$IF_LAN"  -p icmp -j DROP
iptables -A FORWARD -i "$IF_LAN"  -o "$IF_INET" -p icmp -j DROP
iptables -A FORWARD -i "$IF_INET" -o "$IF_LAN"  -p icmp -j DROP
iptables -A FORWARD -i "$IF_DMZ"  -o "$IF_INET" -p icmp -j DROP
iptables -A FORWARD -i "$IF_INET" -o "$IF_DMZ"  -p icmp -j DROP

# ------------------------------------------------------------------------------
# 1) LAN -> WAN : autoriser la sortie Internet utilisateur
# ------------------------------------------------------------------------------

iptables -A FORWARD \
  -i "$IF_LAN" -o "$IF_WAN" \
  -s "$LAN_NET" \
  -m conntrack --ctstate NEW -j ACCEPT

# ------------------------------------------------------------------------------
# 2) LAN -> DMZ : web, FTP, SSH
# ------------------------------------------------------------------------------

# HTTP/HTTPS vers la DMZ (web_dmz, DVWA, etc.)
iptables -A FORWARD \
  -i "$IF_LAN" -o "$IF_DMZ" \
  -s "$LAN_NET" \
  -p tcp -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW -j ACCEPT

# Accès dédié HTTP vers web_dmz (10.30.0.20:80) – utile pour la doc/tests
iptables -A FORWARD \
  -i "$IF_LAN" -o "$IF_DMZ" \
  -s "$LAN_NET" -d "$WEB_DMZ_IP" \
  -p tcp --dport 80 \
  -m conntrack --ctstate NEW -j ACCEPT

iptables -A FORWARD \
  -i "$IF_LAN" -o "$IF_DMZ" \
  -s "$LAN_NET" -d "$FTP_DMZ_IP" \
  -p tcp -m multiport --dports 21,21000:21010 \
  -m conntrack --ctstate NEW -j ACCEPT

# SSH vers ssh_dmz (10.30.0.60:22)
iptables -A FORWARD \
  -i "$IF_LAN" -o "$IF_DMZ" \
  -s "$LAN_NET" -d "$SSH_DMZ_IP" \
  -p tcp --dport 22 \
  -m conntrack --ctstate NEW -j ACCEPT

# ------------------------------------------------------------------------------
# 3) DMZ -> WAN : DNS + HTTP/HTTPS + ICMP (updates / sorties limitées)
# ------------------------------------------------------------------------------

# DNS (UDP)
iptables -A FORWARD \
  -i "$IF_DMZ" -o "$IF_WAN" \
  -s "$DMZ_NET" \
  -p udp --dport 53 \
  -m conntrack --ctstate NEW -j ACCEPT

# DNS + HTTP/HTTPS (TCP)
iptables -A FORWARD \
  -i "$IF_DMZ" -o "$IF_WAN" \
  -s "$DMZ_NET" \
  -p tcp -m multiport --dports 53,80,443 \
  -m conntrack --ctstate NEW -j ACCEPT

# ICMP (diag vers Internet)
iptables -A FORWARD \
  -i "$IF_DMZ" -o "$IF_WAN" \
  -s "$DMZ_NET" \
  -p icmp \
  -m conntrack --ctstate NEW -j ACCEPT

# ------------------------------------------------------------------------------
# 4) DMZ -> LAN : BLOQUÉ (policy)
# ------------------------------------------------------------------------------

# (rien à ajouter : aucune règle ACCEPT -> donc DMZ->LAN reste bloqué)

# ------------------------------------------------------------------------------
# 5) INET -> WAN : machine d'attaque doit avoir Internet
# ------------------------------------------------------------------------------

iptables -A FORWARD \
  -i "$IF_INET" -o "$IF_WAN" \
  -s "$INET_NET" \
  -m conntrack --ctstate NEW -j ACCEPT

# ------------------------------------------------------------------------------
# 6) INET -> DMZ : accès uniquement aux services exposés (web + FTP)
# ------------------------------------------------------------------------------

# HTTP/HTTPS vers toute la DMZ (tests nmap, dvwa, etc.)
iptables -A FORWARD \
  -i "$IF_INET" -o "$IF_DMZ" \
  -s "$INET_NET" \
  -p tcp -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW -j ACCEPT

# FTP (control + passif 21000-21010) vers ftp_dmz
iptables -A FORWARD \
  -i "$IF_INET" -o "$IF_DMZ" \
  -s "$INET_NET" -d "$FTP_DMZ_IP" \
  -p tcp -m multiport --dports 21,21000:21010 \
  -m conntrack --ctstate NEW -j ACCEPT

# ------------------------------------------------------------------------------
# 7) INET -> LAN : RESTE BLOQUÉ
#    => aucune règle ACCEPT, FORWARD DROP s'applique.
# ------------------------------------------------------------------------------

echo "[firewall] Politique appliquée."
iptables -S
iptables -t nat -S
