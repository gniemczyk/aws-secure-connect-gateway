#!/bin/sh
set -e

# ============================================================
# Ephemeral Bastion - Start Script
# 1. Generuje klucze SSH hosta
# 2. Uruchamia sshd
# 3. Nawiązuje tunel TCP przez bore.pub
# ============================================================

# Trap handler - cleanup przy wyjściu
cleanup() {
    echo "INFO: Zamykanie bastionu..."
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
echo "[1/3] Generowanie kluczy hosta SSH..."

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
    echo "  -> ed25519 host key OK"
fi

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N "" -q
    echo "  -> rsa host key OK"
fi

# --- KROK 2: Uruchomienie sshd ---
echo "[2/3] Uruchamianie sshd na porcie 22..."
echo "  -> Login: root (bez hasla)"

/usr/sbin/sshd -e
sleep 1

if ! pgrep -x sshd > /dev/null 2>&1; then
    echo "ERROR: sshd nie uruchomil sie!"
    exit 1
fi
echo "  -> sshd dziala"

# --- KROK 3: Tunel TCP przez bore.pub ---
echo "[3/3] Nawiazywanie tunelu TCP..."

BORE_PORT="${BORE_PORT:-22222}"
echo "  Port TCP na bore.pub: ${BORE_PORT}"

echo "=========================================="
echo " POLACZENIE:"
echo " ssh -p ${BORE_PORT} root@bore.pub"
echo "=========================================="

# bore local <local_port> --to <server> --port <remote_port>
# Tunel TCP: bore.pub:BORE_PORT -> localhost:22 (nasz sshd)
exec bore local 22 --to bore.pub --port "${BORE_PORT}"
