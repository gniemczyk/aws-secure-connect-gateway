#!/bin/sh

# Kontener bastionu - dziala nieprzerwanie dla dostepu przez ECS Exec
echo "=========================================="
echo " Ephemeral Bastion READY"
echo " Polacz sie przez: aws ecs execute-command"
echo "=========================================="
echo ""
echo "Kontener aktywny. Czekam na polaczenie..."

# Utrzymuj kontener przy zyciu (sleep w petli)
while true; do
    sleep 60
done
