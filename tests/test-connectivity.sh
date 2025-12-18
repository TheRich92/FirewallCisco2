#!/usr/bin/env bash
set -u

#########################################################
# VALIDATION GLOBALE INFRASTRUCTURE & FIREWALL
# Mini-Projet Docker - Firewall
#########################################################

# --------- COULEURS ---------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --------- CONFIG IP ---------
ROUTER_LAN="10.20.0.254"
WEB_DMZ="10.30.0.20"
SSH_DMZ="10.30.0.60"
FTP_DMZ="10.30.0.50"

# --------- CONTENEURS ---------
PC_LAN="pc_lan"
PC_DMZ="pc_dmz"
PC_INTERNET="pc_internet"

echo -e "${BLUE}=============================================================${NC}"
echo -e "${BLUE} VALIDATION INFRASTRUCTURE & FIREWALL (Étapes 1 & 2) ${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# =========================================================
# FONCTIONS
# =========================================================

expect_success() {
    local desc="$1"
    local cmd="$2"

    echo -n "✔ $desc ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[ECHEC]${NC}"
        echo -e "   Commande : $cmd"
    fi
}

expect_block() {
    local desc="$1"
    local cmd="$2"

    echo -n "✖ $desc (Doit être BLOQUÉ) ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${RED}[CRITIQUE]${NC} ❌ Trafic autorisé"
    else
        echo -e "${GREEN}[OK - BLOQUÉ]${NC}"
    fi
}

# =========================================================
# 1. ÉTAT DES CONTENEURS
# =========================================================

echo -e "\n${YELLOW}--- 1. Vérification des conteneurs ---${NC}"

for c in $PC_LAN $PC_DMZ $PC_INTERNET; do
    docker ps --format '{{.Names}}' | grep -q "^$c$" \
        && echo -e "• $c : ${GREEN}UP${NC}" \
        || echo -e "• $c : ${RED}DOWN${NC}"
done

# =========================================================
# 2. ROUTAGE & CONNECTIVITÉ
# =========================================================

echo -e "\n${YELLOW}--- 2. Routage & Accès réseau ---${NC}"

expect_success "LAN → Routeur (Ping)" \
    "docker exec $PC_LAN ping -c 1 -W 2 $ROUTER_LAN"

expect_success "LAN → Internet réel (Ping 1.1.1.1)" \
    "docker exec $PC_LAN ping -c 1 -W 2 1.1.1.1"

# =========================================================
# 3. ACCÈS AUTORISÉS (ALLOW)
# =========================================================

echo -e "\n${YELLOW}--- 3. Accès légitimes autorisés ---${NC}"

expect_success "LAN → DMZ Web (HTTP)" \
    "docker exec $PC_LAN curl -I --connect-timeout 2 http://$WEB_DMZ"

expect_success "Internet → DMZ Web (HTTP)" \
    "docker exec $PC_INTERNET curl -I --connect-timeout 2 http://$WEB_DMZ"

expect_success "Internet → DMZ FTP (Port 21)" \
    "docker exec $PC_INTERNET nc -z -w 2 $FTP_DMZ 21"

# =========================================================
# 4. SÉCURITÉ & BLOQUAGES (DROP)
# =========================================================

echo -e "\n${YELLOW}--- 4. Blocages Firewall ---${NC}"

expect_block "Internet → LAN (Ping)" \
    "docker exec $PC_INTERNET ping -c 1 -W 2 10.20.0.10"

expect_block "Internet → DMZ SSH (22)" \
    "docker exec $PC_INTERNET nc -z -w 2 $SSH_DMZ 22"

expect_block "Internet → DMZ MySQL (3306)" \
    "docker exec $PC_INTERNET nc -z -w 2 $WEB_DMZ 3306"

expect_block "DMZ → LAN (Ping)" \
    "docker exec $PC_DMZ ping -c 1 -W 2 10.20.0.10"

# =========================================================
# FIN
# =========================================================

echo -e "\n${BLUE}=============================================================${NC}"
echo -e "${BLUE} FIN DE LA VALIDATION ${NC}"
echo -e "${BLUE}=============================================================${NC}"
