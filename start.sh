#!/bin/sh

# Bastion container - keeps running for ECS Exec access
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
