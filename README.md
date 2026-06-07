# AWS Secure Connect Gateway

Efemeryczny bastion oparty na AWS ECS Fargate z dostępem przez ECS Exec (AWS Systems Manager).

## Jak działa

1. GitHub Workflow uruchamia kontener w ECS Fargate (wewnątrz Twojego VPC)
2. Łączysz się przez `aws ecs execute-command` (SSM Session Manager)
3. Masz shell wewnątrz VPC - możesz łączyć się do baz danych, serwisów itp.
4. Workflow STOP usuwa wszystkie zasoby

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
| `AWS_ACCOUNT_ID` | `123456789012` |

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

### Przykłady użycia wewnątrz bastionu

Po połączeniu masz shell Alpine Linux z narzędziami:

```bash
# Sprawdzenie połączenia do RDS
ncat -zv mydb.abc123.eu-north-1.rds.amazonaws.com 5432

# Zapytanie do API wewnętrznego
curl http://internal-service.local:8080/health

# DNS lookup
dig internal-service.local

# Sprawdzenie dostępności hosta
ncat -zv 10.0.1.50 3306
```

### Tunelowanie połączeń

#### 1. Bezpośredni dostęp z poziomu bastionu

W otwartej sesji bastionu możesz bezpośrednio łączyć się do zasobów VPC używając preinstalowanych klientów:

```bash
# PostgreSQL
psql -h mydb.abc123.eu-north-1.rds.amazonaws.com -U admin -d mydb

# MySQL
mysql -h mydb.abc123.eu-north-1.rds.amazonaws.com -u admin -p mydb

# Redis/ElastiCache
redis-cli -h cache.abc123.ng.0001.eun1.cache.amazonaws.com -p 6379

# Sprawdzenie łączności do API wewnętrznego
curl http://internal-service.local:8080/health
```

#### 2. Port forwarding wewnątrz bastionu za pomocą socat

Jeśli chcesz dostęp z innych procesów w bastionie, użyj `socat` do forwarda portów:

```bash
# Forward port RDS na localhost:5432 wewnątrz bastionu
socat TCP-LISTEN:5432,reuseaddr,fork TCP:mydb.abc123.eu-north-1.rds.amazonaws.com:5432 &

# Teraz sprawdź dostęp z innego shella w tym bastionie
ncat -zv 127.0.0.1 5432

# Łączenie się przez localhost
psql -h 127.0.0.1 -U admin -d mydb
```

#### 3. SSH Port Forwarding z lokalnego komputera

Jeśli chcesz tunelować dostęp z Twojego komputera do bastionu, użyj SSH tunneling przez SSM Session Manager.

Najpierw przygotuj SSM Session Manager do port forwardingu (install session-manager-plugin na Twoim komputerze):

```bash
# Na swoim komputerze - utwórz SSH tunnel przez SSM Session Manager
aws ssm start-session --target i-1234567890abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters "localPortNumber=5432,portNumber=5432,host=mydb.abc123.eu-north-1.rds.amazonaws.com"

# Wtedy w innym terminalu łącz się do RDS przez localhost:5432
psql -h localhost -U admin -d mydb
```

Lub jeśli bastion ma SSH dostęp (z Elastic IP):

```bash
# Na swoim komputerze - SSH tunnel
ssh -L 5432:mydb.abc123.eu-north-1.rds.amazonaws.com:5432 \
    -i your_key user@bastion-public-ip

# Wtedy łącz się do RDS przez localhost
psql -h localhost -U admin -d mydb
```

**Dostępne narzędzia w bastionie:** `socat`, `ncat`, `curl`, `dig`, `psql`, `mysql`, `redis-cli`

## Struktura projektu

```
.
├── .github/workflows/
│   └── deploy-bastion.yml    # GitHub Actions workflow
├── terraform/
│   ├── backend.tf            # S3 backend
│   ├── main.tf               # ECS, IAM, networking
│   ├── variables.tf          # Zmienne
│   └── outputs.tf            # Outputy
├── Dockerfile                # Alpine + narzędzia sieciowe
├── start.sh                  # Keepalive script
└── README.md
```

## Zasoby tworzone przez Terraform

| Zasób | Cel |
|-------|-----|
| ECS Cluster | Hosting kontenerów |
| ECS Service (desired=1) | Utrzymuje dokładnie 1 task |
| ECS Task Definition | Definicja kontenera |
| IAM Execution Role | Pulling images, logi |
| IAM Task Role + SSM Policy | ECS Exec (session manager) |
| Subnet | Tymczasowa podsieć w VPC |
| Route Table + IGW route | Dostęp do internetu (ECR pull) |
| Security Group | Outbound only (brak inbound) |
| CloudWatch Log Group | Logi kontenera (1 dzień retencji) |

## Troubleshooting

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