#!/bin/sh

# Kontener bastionu - dziala nieprzerwanie dla dostepu przez ECS Exec
echo "=========================================="
echo " Ephemeral Bastion READY"
echo " Polacz sie przez: aws ecs execute-command"
echo "=========================================="
echo ""
echo "Dostepne pakiety do instalacji na zadanie:"
echo "  curl jq aws-cli        - HTTP/API tools"
echo "  postgresql-client      - psql"
echo "  mysql-client           - mysql"
echo "  redis                  - redis-cli"
echo "  nmap-ncat socat        - network tools"
echo "  tcpdump                - packet analyzer"
echo "  bind-tools             - dig, nslookup"
echo "  openssh-client         - ssh, scp"
echo ""
echo "Instalacja: apk add <pakiet>"
echo ""
echo "Kontener aktywny. Czekam na polaczenie..."

# Utrzymuj kontener przy zyciu (sleep w petli)
while true; do
    sleep 60
done
