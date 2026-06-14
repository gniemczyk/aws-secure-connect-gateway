# AWS Secure Connect Gateway

Efemeryczny bastion oparty na AWS ECS Fargate z dostępem przez ECS Exec (AWS Systems Manager).

## Jak działa

1. GitHub Workflow uruchamia kontener w ECS Fargate (wewnątrz Twojego VPC). Przy uruchomieniu można zdefiniować wyrażenie cron dla czasu wyłączenia.
2. Automatycznie tworzona jest reguła **AWS EventBridge Scheduler**, która wyłączy bastion o wybranej godzinie (domyślnie codziennie o 23:00 UTC), chroniąc przed generowaniem kosztów przez noc.
3. **CloudWatch Alarm** monitoruje błędy Lambda i alert w razie niepowodzenia auto-stopu.
4. Łączysz się za pomocą lokalnego skryptu `./connect.sh` (oferuje menu z opcjami interaktywnej sesji shell lub tunelu port forwarding bezpośrednio na Twój komputer). Jeśli bastion został wyłączony przez auto-stop, skrypt umożliwia ponowne uruchomienie bez użycia GitHub Actions (z opcją zmiany harmonogramu auto-stop).
5. Wszystkie polecenia wpisywane w sesjach są audytowane i zapisywane w **AWS CloudWatch Logs** (strukturalne logowanie z Python logger).
6. Ręczne wywołanie workflow **STOP** (lub automatyczny harmonogram) zatrzymuje/usuwa tymczasowe zasoby.

```
Twój komputer
     ↓  aws ecs execute-command (SSM, szyfrowane)
AWS ECS Fargate Task (wewnątrz VPC)
     ↓  bezpośredni dostęp sieciowy
Zasoby VPC (RDS, ElastiCache, EC2, itp.)
```

## Quick Start

### 1. Wymagania na Twoim komputerze

```bash
# AWS CLI
brew install awscli

# Session Manager Plugin (wymagany dla ECS Exec)
brew install --cask session-manager-plugin
```

### 2. GitHub Secrets

Settings → Secrets and variables → Actions → Secrets:

| Secret | Wartość |
|--------|---------|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-role` |

### 3. GitHub Variables

Settings → Secrets and variables → Actions → Variables:

| Variable | Wartość |
|----------|---------|
| `VPC_ID` | `vpc-xxxxxxxx` |
| `AWS_REGION` | `eu-north-1` |
| `TFSTATE_REGION` | `eu-north-1` |

### 4. AWS - jednorazowa konfiguracja OIDC

1. IAM → Identity Providers → Add provider:
   - Type: OpenID Connect
   - URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. Utwórz rolę IAM z trust policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringLike": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:TWOJ_USER/secure-connect-gateway:*"
      }
    }
  }]
}
```

3. Przypisz uprawnienia do roli:
   - `AmazonECS_FullAccess`
   - `AmazonVPCFullAccess`
   - `CloudWatchLogsFullAccess`
   - `IAMFullAccess` (dla tworzenia task roles)
   - `AmazonSSMFullAccess` (dla ECS Exec)

## Użycie

### START - uruchomienie bastionu

1. GitHub → Actions → "Efemeryczny Bastion ECS Fargate" → Run workflow
2. Akcja: **START**
3. Po zakończeniu w logach kroku "Podsumowanie" zobaczysz komendę:

```bash
aws ecs execute-command --cluster ephemeral-bastion-cluster --task TASK_ID --interactive --command "/bin/sh" --region eu-north-1
```

4. Skopiuj i wklej na swoim terminalu - masz shell wewnątrz VPC.

### STOP - zatrzymanie bastionu

1. GitHub → Actions → Run workflow
2. Akcja: **STOP**
3. Wszystkie zasoby zostaną usunięte

### Ponowne uruchomienie po auto-stop (bez GitHub Actions)

Gdy bastion został wyłączony przez harmonogram (EventBridge cron), nie musisz wchodzić w GitHub Actions - wystarczy uruchomić skrypt:

```bash
./connect.sh
```

#### Konfiguracja connect.sh

Na początku skryptu znajduje się domyślna nazwa bastionu (taka sama jak w Terraform i GitHub Actions):

```bash
DEFAULT_BASTION_NAME="ephemeral-bastion"
```

Skrypt zapyta o nazwę bastionu (Enter = domyślna). Z niej automatycznie wyznacza nazwy zasobów:
- Klaster: `{nazwa}-cluster`
- Serwis: `{nazwa}-service`
- EventBridge rule: `{nazwa}-auto-stop`

Można też pominąć pytanie przez zmienną środowiskową:

```bash
BASTION_NAME=my-bastion ./connect.sh
```

#### Jak działa restart

Skrypt wykryje brak running taska i zaproponuje:
1. Ponowne uruchomienie bastionu (`aws ecs update-service --desired-count 1`)
2. Zmianę harmonogramu auto-stop (np. `cron(0 21 * * ? *)` = 21:00 UTC)
3. Poczeka na uruchomienie taska i SSM Agenta
4. Przejdzie do menu (shell / port forwarding)

### CI Gate - walidacja przed deploy

Workflow `lint-and-scan.yml` uruchamia się automatycznie na push do `main`. Jeśli walidacja Terraform lub skanowanie bezpieczeństwa nie przejdzie, workflow deploy (`Efemeryczny Bastion ECS Fargate`) zostanie zablokowany na branchu `main` do czasu naprawienia błędów.

### Przykłady użycia wewnątrz bastionu

Po połączeniu masz minimalny shell Alpine Linux. Instalujesz tylko potrzebne narzędzia:

```bash
# Instalacja narzędzi sieciowych
apk add curl bind-tools nmap-ncat

# Sprawdzenie połączenia do RDS
ncat -zv mydb.abc123.eu-north-1.rds.amazonaws.com 5432

# Zapytanie do API wewnętrznego
curl http://internal-service.local:8080/health

# DNS lookup
dig internal-service.local
```

### Tunelowanie połączeń

#### 1. Bezpośredni dostęp z poziomu bastionu

W otwartej sesji bastionu możesz łączyć się do zasobów VPC po instalacji odpowiednich klientów:

```bash
# PostgreSQL
apk add postgresql-client
psql -h mydb.abc123.eu-north-1.rds.amazonaws.com -U admin -d mydb

# MySQL
apk add mysql-client
mysql -h mydb.abc123.eu-north-1.rds.amazonaws.com -u admin -p mydb

# Redis/ElastiCache
apk add redis
redis-cli -h cache.abc123.ng.0001.eun1.cache.amazonaws.com -p 6379

# Sprawdzenie łączności do API wewnętrznego
apk add curl
curl http://internal-service.local:8080/health
```

#### 2. Port forwarding wewnątrz bastionu za pomocą socat

Jeśli chcesz dostęp z innych procesów w bastionie, użyj `socat` do forwarda portów:

```bash
# Instalacja socat
apk add socat

# Forward port RDS na localhost:5432 wewnątrz bastionu
socat TCP-LISTEN:5432,reuseaddr,fork TCP:mydb.abc123.eu-north-1.rds.amazonaws.com:5432 &

# Teraz sprawdź dostęp z innego shella w tym bastionie
apk add nmap-ncat
ncat -zv 127.0.0.1 5432

# Łączenie się przez localhost
apk add postgresql-client
psql -h 127.0.0.1 -U admin -d mydb
```

**Narzędzia do instalacji na żądanie:**
```bash
apk add curl jq aws-cli           # HTTP/API tools
apk add postgresql-client         # psql
apk add mysql-client              # mysql
apk add redis                     # redis-cli
apk add nmap-ncat socat tcpdump   # network tools
apk add bind-tools                # dig, nslookup
apk add openssh-client            # ssh, scp
apk add vim nano                  # edytory
```

#### 3. Lokalne tunelowanie bezpośrednio na Twój komputer (SSM Port Forwarding)

Zamiast przekierowywać porty wewnątrz kontenera za pomocą `socat` i uruchamiać klientów bezpośrednio w bastionie, możesz przekierować porty bezpośrednio ze swojego komputera do dowolnego zasobu w VPC (np. RDS) za pomocą tunelu SSM Session Manager. Ułatwia to używanie lokalnych narzędzi GUI (np. DBeaver, pgAdmin, Redis Insight).

Aby to zrobić, uruchom lokalnie skrypt:
```bash
./connect.sh
```
Skrypt zapyta o:
- Wybór profilu AWS (jeśli masz wiele)
- Wybór regionu (lub użyj z konfiguracji)
- Opcję połączenia (shell lub port forwarding)

Wybierz opcję `2) Port Forwarding` i podaj dane hosta docelowego w VPC (np. endpoint bazy danych) oraz porty. Skrypt automatycznie zestawi bezpieczny tunel.

## Struktura projektu

```
.
├── .github/workflows/
│   ├── deploy-bastion.yml    # GitHub Actions workflow (START/STOP)
│   └── lint-and-scan.yml     # Workflow CI (format, validate, Trivy) - blokuje deploy przy bledach
├── terraform/
│   ├── backend.tf            # S3 backend
│   ├── main.tf               # ECS, IAM, networking, EventBridge Scheduler
│   ├── lambda_stop.py        # Lambda auto-stop (Python) - pakowana przez archive_file
│   ├── variables.tf          # Zmienne
│   └── outputs.tf            # Outputy
├── Dockerfile                # Minimal Alpine (~5-7 MB) - pakiety instalowane na żądanie
├── start.sh                  # Keepalive script
├── connect.sh                # Lokalny skrypt do laczenia, tunelowania i restartu bastionu (SSM)
└── README.md
```

## Zasoby tworzone przez Terraform

| Zasób | Cel |
|-------|-----|
| ECR Repository | Przechowywanie obrazów Docker (max 2 obrazy) |
| ECR Lifecycle Policy | Automatyczne usuwanie starych obrazów |
| ECS Cluster | Hosting kontenerów |
| ECS Service (desired=1) | Utrzymuje dokładnie 1 task z healthcheck |
| ECS Task Definition | Definicja kontenera z healthcheck |
| IAM Execution Role | Pulling images, logi |
| IAM Task Role + SSM Policy | ECS Exec (session manager) |
| Lambda Function | Auto-stop przez EventBridge (retry policy) |
| EventBridge Rule | Harmonogram cron (np. 23:00 UTC) |
| IAM Lambda Role | Uprawnienia Lambda do ECS UpdateService |
| Subnet | Tymczasowa podsieć w VPC |
| Route Table + IGW route | Dostęp do internetu (ECR pull) |
| Security Group | Outbound only (brak inbound) |
| CloudWatch Log Group | Logi kontenera (1 dzień retencji) |
| CloudWatch Log Group | Logi Lambda (1 dzień retencji) |
| CloudWatch Metric Alarm | Monitoring błędów Lambda auto-stop |

## Troubleshooting

### Lambda auto-stop zwraca błąd

Sprawdź logi Lambda w CloudWatch:

```bash
aws logs tail "/aws/lambda/ephemeral-bastion-auto-stop" --region eu-north-1 --follow
```

Jeśli CloudWatch Alarm `ephemeral-bastion-auto-stop-errors` jest w stanie **ALARM**, oznacza to że Lambda miała błąd przy próbie zatrzymania bastionu (zwykle: błąd parametrów AWS API, brak uprawnień IAM).

### "TargetNotConnectedException" przy execute-command

SSM agent potrzebuje 30-60 sekund po starcie taska. Poczekaj i spróbuj ponownie.

```bash
# Sprawdź czy ECS Exec jest włączony na tasku:
aws ecs describe-tasks --cluster ephemeral-bastion-cluster --tasks TASK_ID \
  --region eu-north-1 --query 'tasks[0].enableExecuteCommand'
```

Jeśli zwraca `false` - uruchom workflow ponownie (START).

### "Session Manager Plugin not found"

```bash
brew install --cask session-manager-plugin
```

### Task nie uruchamia się

- Sprawdź CloudWatch Logs: `/ecs/ephemeral-bastion`
- Sprawdź czy VPC ma Internet Gateway
- Sprawdź czy rola IAM ma uprawnienia ECS + ECR

### Terraform błędy przy powtórnym START

Workflow automatycznie importuje istniejące zasoby. Jeśli nadal są błędy - uruchom STOP, potem START.

## Bezpieczeństwo

- **Brak inbound**: Security Group blokuje cały ruch przychodzący
- **IAM auth**: Dostęp tylko przez uwierzytelnione AWS credentials
- **Efemeryczność**: Zasoby usuwane po STOP
- **Szyfrowanie**: SSM Session Manager szyfruje ruch end-to-end
- **Audyt**: CloudTrail loguje kto i kiedy łączył się przez ECS Exec
- **Brak SSH/portów/tuneli**: Żadne porty nie są wystawione publicznie

---
**Autor:** Grzegorz N  
**Data:** Czerwiec 2026