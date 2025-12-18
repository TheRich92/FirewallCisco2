#!/usr/bin/env bash
set -u

# --- COULEURS POUR LE RAPPORT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=============================================================${NC}"
echo -e "${BLUE}       VALIDATION GLOBALE INFRASTRUCTURE & FIREWALL          ${NC}"
echo -e "${BLUE}       (Étapes 1 & 2 du Mini-Projet)                         ${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# --- FONCTIONS DE TEST ---

# Test qui DOIT réussir (Accès légitime)
expect_success() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Test : $test_name ... "
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[ECHEC]${NC} (La commande a échoué)"
        echo -e "  Commande : $command"
    fi
}

# Test qui DOIT échouer (Blocage Firewall)
expect_block() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Test : $test_name (Doit être bloqué) ... "
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${RED}[CRITIQUE]${NC} Le trafic est passé alors qu'il devrait être bloqué !"
    else
        echo -e "${GREEN}[OK - BLOQUÉ]${NC}"
    fi
}

# --- 1. VÉRIFICATION DES CONTENEURS ---
echo -e "${YELLOW}--- 1. État des Conteneurs ---${NC}"
if [ $(docker ps | grep -c "Up") -ge 8 ]; then
    echo -e "${GREEN}[OK]${NC} Tous les conteneurs semblent démarrés."
else
    echo -e "${RED}[ATTENTION]${NC} Certains conteneurs ne sont pas lancés :"
    docker ps --format "table {{.Names}}\t{{.Status}}"
fi
echo ""

# --- 2. TESTS ROUTAGE & NAT (Étape 1) ---
echo -e "${YELLOW}--- 2. Routage & Accès Internet (LAN) ---${NC}"

expect_success "LAN -> Internet (Ping 1.1.1.1)" \
    "docker exec pc_lan ping -c 1 -W 2 1.1.1.1"

expect_success "LAN -> Routeur (Ping Gateway)" \
    "docker exec pc_lan ping -c 1 10.20.0.254"

echo ""

# --- 3. TESTS SERVICES AUTORISÉS (Étape 2 - Allow) ---
echo -e "${YELLOW}--- 3. Accès Légitimes (Firewall Allow) ---${NC}"

# A. Depuis le LAN (Admin)
expect_success "LAN -> DMZ Web (HTTP)" \
    "docker exec pc_lan curl -s -I --connect-timeout 2 http://10.30.0.20"

expect_success "LAN -> DMZ SSH (Port 22)" \
    "docker exec pc_lan nc -zv -w 2 10.30.0.60 22"

expect_success "LAN -> DMZ FTP (Port 21)" \
    "docker exec pc_lan curl -s ftp://user:pass@10.30.0.50/"

expect_success "LAN -> Routeur SNMP (UDP 161)" \
    "docker exec pc_lan snmpwalk -v2c -c public 10.20.0.254 .1.3.6.1.2.1.1"

# B. Depuis Internet (Public)
expect_success "Internet -> DMZ Web (HTTP)" \
    "docker exec pc_internet curl -s -I --connect-timeout 2 http://10.30.0.20"

expect_success "Internet -> DMZ FTP (Passif)" \
    "docker exec pc_internet curl -s --max-time 5 ftp://user:pass@10.30.0.50/"

echo ""

# --- 4. TESTS SÉCURITÉ / BLOCAGE (Étape 2 - Drop) ---
echo -e "${YELLOW}--- 4. Sécurité & Blocages (Firewall Drop) ---${NC}"

# A. Protection du LAN
expect_block "Internet -> LAN (Ping interdit)" \
    "docker exec pc_internet ping -c 1 -W 1 10.20.0.10"

# B. Protection du SSH (Admin seulement)
expect_block "Internet -> DMZ SSH (Port 22 interdit)" \
    "docker exec pc_internet nc -zv -w 2 10.30.0.60 22"

# C. Isolation DMZ -> LAN
expect_block "DMZ (Web) -> LAN (Ping interdit)" \
    "docker exec web_dmz ping -c 1 -W 1 10.20.0.10"

expect_block "DMZ (SSH) -> LAN (Connect interdit)" \
    "docker exec ssh_dmz nc -zv -w 1 10.20.0.10 80"

echo ""
echo -e "${BLUE}=============================================================${NC}"
echo -e "${BLUE}                   FIN DE LA VALIDATION                      ${NC}"
echo -e "${BLUE}=============================================================${NC}"