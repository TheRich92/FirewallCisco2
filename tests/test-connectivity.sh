#!/usr/bin/env bash
set -euo pipefail

say() { printf "\n=== %s ===\n" "$*"; }

say "Infos interfaces (routerfw)"
docker exec routerfw bash -lc 'ip -4 -o addr show; echo; ip route'

say "PING routeur depuis pc_lan"
docker exec pc_lan bash -lc 'ping -c1 10.20.0.254 && echo OK || echo KO'

say "PING routeur depuis pc_dmz"
docker exec pc_dmz bash -lc 'ping -c1 10.30.0.254 && echo OK || echo KO'

say "PING routeur depuis pc_internet"
docker exec pc_internet bash -lc 'ping -c1 10.10.0.254 && echo OK || echo KO'

say "PING inter-segments via router (LAN -> DMZ & INET)"
docker exec pc_lan bash -lc 'ping -c1 10.30.0.10 && echo "LAN->DMZ OK (en Étape 2 on filtrera)" || echo "LAN->DMZ KO"'
docker exec pc_lan bash -lc 'ping -c1 10.10.0.10 && echo "LAN->INET OK" || echo "LAN->INET KO"'

say "PING inter-segments via router (DMZ -> LAN & INET)"
docker exec pc_dmz bash -lc 'ping -c1 10.20.0.10 && echo "DMZ->LAN OK" || echo "DMZ->LAN KO"'
docker exec pc_dmz bash -lc 'ping -c1 10.10.0.10 && echo "DMZ->INET OK" || echo "DMZ->INET KO"'

say "PING inter-segments via router (INET -> LAN & DMZ)"
docker exec pc_internet bash -lc 'ping -c1 10.20.0.10 && echo "INET->LAN OK" || echo "INET->LAN KO"'
docker exec pc_internet bash -lc 'ping -c1 10.30.0.10 && echo "INET->DMZ OK" || echo "INET->DMZ KO"'

say "Test sortie Internet (DNS 1.1.1.1) depuis pc_lan (peut échouer si WAN bloqué par l’hôte)"
docker exec pc_lan bash -lc 'ping -c1 1.1.1.1 && echo "Sortie Internet OK (NAT WAN)" || echo "Sortie Internet KO"'

