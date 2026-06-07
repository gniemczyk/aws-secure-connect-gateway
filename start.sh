#!/bin/sh
set -e

# ============================================================
# Ephemeral Bastion - Start Script
# 1. Generuje klucze SSH (host keys + client key dla Serveo)
# 2. Konfiguruje authorized_keys z env var
# 3. Uruchamia sshd
# 4. Nawiązuje tunel Serveo.net
# ============================================================

# Trap handler - cleanup przy wyjściu
cleanup() {
    echo "INFO: Zamykanie bastionu..."
    # Zatrzymaj sshd jeśli działa
    if [ -f /run/sshd/sshd.pid ]; then
        kill "$(cat /run/sshd/sshd.pid)" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup EXIT INT TERM

echo "=========================================="
echo " Ephemeral Bastion - Inicjalizacja"
echo "=========================================="

# --- KROK 1: Generowanie host keys dla sshd ---
echo "[1/4] Generowanie kluczy hosta SSH..."

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
    echo "  -> Wygenerowano ed25519 host key"
fi

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N "" -q
    echo "  -> Wygenerowano rsa host key"
fi

# --- KROK 2: Konfiguracja dostępu ---
echo "[2/4] Konfiguracja dostepu SSH..."
echo "  -> Login: ssh -J serveo.net root@<subdomena>"
echo "  -> Bezposredni dostep (bez hasla)"

# --- KROK 3: Uruchomienie sshd ---
echo "[3/4] Uruchamianie sshd na porcie 22..."

/usr/sbin/sshd -e
echo "  -> sshd uruchomiony"

# Weryfikacja że sshd działa
sleep 1
if ! pgrep -x sshd > /dev/null 2>&1; then
    echo "ERROR: sshd nie uruchomił się!"
    exit 1
fi

# --- KROK 4: Tunel Serveo.net ---
echo "[4/4] Nawiązywanie tunelu Serveo.net..."

SERVEO_SUBDOMAIN="${SERVEO_SUBDOMAIN:-ephemeral-bastion}"
echo "  Żądana subdomena: ${SERVEO_SUBDOMAIN}"

# Generowanie klucza klienta SSH dla Serveo (potrzebny do rezerwacji subdomeny)
SERVEO_KEY="/tmp/serveo_client_key"
if [ ! -f "$SERVEO_KEY" ]; then
    ssh-keygen -t ed25519 -f "$SERVEO_KEY" -N "" -q
    echo "  -> Wygenerowano klucz klienta dla Serveo"
fi

echo "=========================================="
echo " Łączenie z Serveo.net..."
echo " URL: ssh -p 80 root@${SERVEO_SUBDOMAIN}.serveo.net"
echo "=========================================="

# Uruchomienie tunelu SSH do serveo.net
# -R subdomain:80:localhost:22 - Serveo nasłuchuje na subdomain.serveo.net:80
#    i przekierowuje ruch TCP na nasz localhost:22 (sshd)
# -i: klucz klienta (potrzebny do rezerwacji subdomeny)
# -o StrictHostKeyChecking=accept-new: akceptuje klucz serveo przy pierwszym połączeniu
# -o UserKnownHostsFile=/dev/null: nie zapisuje known_hosts (ephemeral)
# -o ServerAliveInterval=60: heartbeat co 60s
# -o ServerAliveCountMax=3: rozłącz po 3 nieudanych heartbeatach
# -o ExitOnForwardFailure=yes: zakończ jeśli tunel się nie ustanowi
# -N: nie uruchamia shell na zdalnym serwerze
# -T: nie przydziela pseudo-terminala

exec ssh -R "${SERVEO_SUBDOMAIN}:80:localhost:22" \
    -i "$SERVEO_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -N \
    -T \
    serveo.net
