#!/usr/bin/env bash

# Skrypt pomocniczy do laczenia sie z efemerycznym bastionem AWS ECS Fargate
# Wymaga zainstalowanego AWS CLI oraz session-manager-plugin

set -e

# Kolory do logow
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # Brak koloru

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}      AWS Secure Connect Gateway - Klient          ${NC}"
echo -e "${BLUE}===================================================${NC}"

# 1. Sprawdzenie zaleznosci
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Błąd: AWS CLI nie jest zainstalowane. Zainstaluj je za pomocą: brew install awscli${NC}"
    exit 1
fi

if ! aws ssm start-session --help &> /dev/null; then
    # Prosta weryfikacja wtyczki ssm
    if ! command -v session-manager-plugin &> /dev/null; then
        echo -e "${RED}Błąd: Wtyczka session-manager-plugin nie jest zainstalowana.${NC}"
        echo -e "${YELLOW}Zainstaluj ją za pomocą: brew install --cask session-manager-plugin${NC}"
        exit 1
    fi
fi

# 2. Konfiguracja zmiennych (mozliwosc nadpisania przez ENV)
CLUSTER_NAME="${CLUSTER_NAME:-ephemeral-bastion-cluster}"
SERVICE_NAME="${SERVICE_NAME:-ephemeral-bastion-service}"

# Wykrywanie regionu AWS
CONFIG_REGION=$(aws configure get region 2>/dev/null || echo "")

if [ -n "$CONFIG_REGION" ]; then
    echo -e "Wykryto region z konfiguracji AWS CLI: ${GREEN}$CONFIG_REGION${NC}"
    read -rp "Czy użyć tego regionu? (T/n): " USE_CONFIG
    if [[ "$USE_CONFIG" =~ ^[Nn]$ ]]; then
        read -rp "Wprowadź region AWS (np. eu-central-1, eu-north-1): " AWS_REGION
    else
        AWS_REGION="$CONFIG_REGION"
    fi
else
    echo -e "${YELLOW}Nie wykryto regionu w konfiguracji AWS CLI${NC}"
    read -rp "Wprowadź region AWS (np. eu-central-1, eu-north-1): " AWS_REGION
fi

if [ -z "$AWS_REGION" ]; then
    AWS_REGION="eu-central-1"
    echo -e "${YELLOW}Użyto domyślnego regionu: eu-central-1${NC}"
fi

echo -e "Region AWS: ${GREEN}$AWS_REGION${NC}"
echo -e "Klaster ECS: ${GREEN}$CLUSTER_NAME${NC}"

# 3. Pobranie aktywnego taska ECS
echo -e "Szukanie działającego kontenera bastionu..."
TASK_ARN=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING \
    --region "$AWS_REGION" \
    --query 'taskArns[0]' \
    --output text 2>/dev/null || echo "")

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
    echo -e "${RED}Błąd: Nie znaleziono uruchomionego kontenera bastionu.${NC}"
    echo -e "${YELLOW}Upewnij się, że uruchomiłeś workflow START w GitHub Actions oraz używasz poprawnego profilu/regionu AWS.${NC}"
    exit 1
fi

TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
echo -e "Znaleziono aktywny Task ID: ${GREEN}$TASK_ID${NC}"

# 4. Pobranie runtime ID kontenera (potrzebne do SSM Port Forwarding)
CONTAINER_INFO=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ID" \
    --region "$AWS_REGION" \
    --query 'tasks[0].containers[0].[name,runtimeId]' \
    --output text 2>/dev/null || echo "")

CONTAINER_NAME=$(echo "$CONTAINER_INFO" | awk '{print $1}')
RUNTIME_ID=$(echo "$CONTAINER_INFO" | awk '{print $2}')

if [ -z "$RUNTIME_ID" ] || [ "$RUNTIME_ID" = "None" ]; then
    echo -e "${RED}Błąd: Nie można pobrać Runtime ID kontenera. Czy kontener zakończył uruchamianie?${NC}"
    exit 1
fi

# Interaktywne menu
echo -e "\n${YELLOW}Wybierz akcję:${NC}"
echo -e "1) Interaktywna sesja Shell (Terminal w bastionie)"
echo -e "2) Port Forwarding (Tunel do bazy danych/serwisu w VPC)"
echo -e "3) Wyjście"
read -rp "Wybór (1-3): " OPTION

case "$OPTION" in
    1)
        echo -e "\n${GREEN}Nawiązywanie połączenia shell z kontenerem...${NC}"
        echo -e "Wpisz 'exit' aby zakończyć sesję."
        aws ecs execute-command \
            --cluster "$CLUSTER_NAME" \
            --task "$TASK_ID" \
            --container "$CONTAINER_NAME" \
            --interactive \
            --command "/bin/sh" \
            --region "$AWS_REGION"
        ;;
    2)
        echo -e "\n${BLUE}--- Konfiguracja Tunelu Port Forwarding ---${NC}"
        read -rp "Podaj host docelowy w VPC (np. mydb.xyz.rds.amazonaws.com): " REMOTE_HOST
        read -rp "Podaj port docelowy (np. 5432 dla PostgreSQL, 3306 dla MySQL): " REMOTE_PORT
        read -rp "Podaj port lokalny (port na Twoim komputerze, np. 5432): " LOCAL_PORT

        SSM_TARGET="ecs:${CLUSTER_NAME}_${TASK_ID}_${RUNTIME_ID}"

        echo -e "\n${GREEN}Uruchamianie tunelu SSM...${NC}"
        echo -e "Możesz teraz połączyć się z ${YELLOW}localhost:${LOCAL_PORT}${NC} -> ${GREEN}${REMOTE_HOST}:${REMOTE_PORT}${NC}"
        echo -e "Wciśnij Ctrl+C aby zamknąć tunel."
        
        aws ssm start-session \
            --target "$SSM_TARGET" \
            --document-name AWS-StartPortForwardingSessionToRemoteHost \
            --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"],\"host\":[\"$REMOTE_HOST\"]}" \
            --region "$AWS_REGION"
        ;;
    3)
        echo -e "Do zobaczenia!"
        exit 0
        ;;
    *)
        echo -e "${RED}Nieprawidłowy wybór.${NC}"
        exit 1
        ;;
esac
