#!/bin/sh
set -e

# Trap handler dla obsługi błędów
trap 'echo "ERROR: SSH tunnel failed or disconnected (exit code: $?)" >&2; exit 1' EXIT

# Pobieranie subdomeny z zmiennej środowiskowej lub użycie domyślnej
SERVEO_SUBDOMAIN="${SERVEO_SUBDOMAIN:-ephemeral-bastion}"

echo "=========================================="
echo "Inicjalizacja tunelu Serveo.net"
echo "=========================================="
echo "Subdomena: ${SERVEO_SUBDOMAIN}"
echo "=========================================="

# Uruchomienie tunelu SSH do serveo.net
# -R: reverse tunnel - przekazuje ruch z portu 80 serveo.net na localhost:22
# -o StrictHostKeyChecking=accept-new: akceptuje nowe klucze bezpiecznie
# -o UserKnownHostsFile=/tmp/serveo_known_hosts: przechowuje klucze tymczasowo
# -o ServerAliveInterval=60: utrzymuje tunel aktywnym (heartbeat co 60s)
# -o ServerAliveCountMax=3: rozłącza po 3 nieudanych heartbeatach (3min timeout)
# -o ExitOnForwardFailure=yes: wychodzi z błędem jeśli tunel się nie ustanowi
# -N: nie uruchamia zdalnego polecenia, tylko tunel
# -T: nie przydziela pseudo-terminala

ssh -R "${SERVEO_SUBDOMAIN}:80:localhost:22" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/tmp/serveo_known_hosts \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -N \
    -T \
    serveo.net

# Jeśli SSH się rozłączy, trap wywoła EXIT i zwróci kod 1
echo "Tunel został zamknięty"
exit 0
