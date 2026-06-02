#!/bin/sh
set -e

# Pobieranie subdomeny z zmiennej środowiskowej lub użycie domyślnej
SERVEO_SUBDOMAIN="${SERVEO_SUBDOMAIN:-ephemeral-bastion}"

echo "=========================================="
echo "Inicjalizacja tunelu Serveo.net"
echo "=========================================="
echo "Subdomena: ${SERVEO_SUBDOMAIN}"
echo "=========================================="

# Uruchomienie tunelu SSH do serveo.net
# -R: reverse tunnel - przekazuje ruch z portu 80 serveo.net na localhost:22
# -o StrictHostKeyChecking=no: pomija weryfikację klucza hosta (serveo.net zmienia klucze)
# -o UserKnownHostsFile=/dev/null: nie zapisuje known_hosts (system plików tylko do odczytu)
# -N: nie uruchamia zdalnego polecenia, tylko tunel
# -T: nie przydziela pseudo-terminala

ssh -R "${SERVEO_SUBDOMAIN}:80:localhost:22" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -N \
    -T \
    serveo.net 2>&1 | tee /dev/stderr

# Jeśli SSH się rozłączy, kontener zakończy działanie
echo "Tunel został zamknięty"
