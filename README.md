# Secure Connect Gateway

Bezpieczny, efemeryczny bastion SSH oparty na AWS ECS Fargate z autoryzacją GitHub OIDC i tunelowaniem przez Serveo.net.

## Architektura

- **ECS Fargate Task**: Kontener uruchamiany w AWS ECS Fargate
- **Serveo.net**: Przezroczysty tunel SSH bez generowania kluczy
- **GitHub OIDC**: Autoryzacja do AWS bez stałych credentials
- **Terraform**: Zarządzanie infrastrukturą jako kod
- **Efemeryczność**: Pełne czyszczenie zasobów po zakończeniu

## Bezpieczeństwo

### Hardening Kontenera
- **Minimalny obraz**: Alpine Linux 3.19 z tylko SSH klientem
- **Non-root user**: Kontener uruchamiany jako użytkownik nobody (UID 65534)
- **Readonly filesystem**: System plików całkowicie zablokowany do zapisu
- **Brak pakietów**: Niemożliwa instalacja pakietów w locie
- **Zablokowany inbound**: Security Group blokuje cały ruch przychodzący
- **Brak capabilities**: Wszystkie Linux capabilities usunięte
- **Brak execute command**: Wyłączona możliwość ECS execute command

### Bezpieczeństwo Sieciowe
- **Tymczasowa podsieć**: Tworzona na czas życia bastionu
- **Security Group**: Zablokowany inbound, outbound tylko na SSH (port 22) i DNS (port 53)
- **Public IP**: Tylko dla połączenia z Serveo.net
- **Ograniczony ruch**: Brak możliwości danych exfiltration

## Wymagania Wstępne - QUICK START

### 1. GitHub Secrets - 1 minute setup
Ustaw w repozytorium GitHub (Settings → Secrets and variables → Actions → Secrets):
- `AWS_ROLE_ARN`: Twoja rola IAM ARN (np. `arn:aws:iam::837175765719:role/github-actions-role`)

### 2. GitHub Variables - 1 minute setup  
Ustaw w repozytorium GitHub (Settings → Secrets and variables → Actions → Variables):
- `VPC_ID`: Twój VPC ID (np. `vpc-12345678`)

### 3. AWS Configuration

Skonfiguruj OIDC w AWS (one-time setup):

1. **Utwórz Identity Provider w AWS IAM Console**:
   ```
   Provider type: OpenID Connect
   Provider URL: https://token.actions.githubusercontent.com
   Audience: sts.amazonaws.com
   ```

2. **Utwórz Rolę IAM z trust policy** (dostosuj do swoich gałęzi):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "Federated": "arn:aws:iam::837175765719:oidc-provider/token.actions.githubusercontent.com"
       },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringLike": {
           "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
           "token.actions.githubusercontent.com:sub": [
             "repo:gniemczyk/*:ref:refs/heads/main",
             "repo:gniemczyk/*:ref:refs/heads/develop"
           ]
         }
       }
     }]
   }
   ```

3. **Przypisz uprawnienia do roli**:
   - `AmazonECS_FullAccess`
   - `AmazonVPCFullAccess`
   - `CloudWatchLogsFullAccess`
   
   Lub dla maksymalnej elastyczności: `AdministratorAccess`

4. **Skopiuj ARN roli** i ustaw jako `AWS_ROLE_ARN` w GitHub Secrets

## Użycie

### Uruchomienie Bastionu (START)

1. Przejdź do GitHub Actions
2. Uruchom workflow "Efemeryczny Bastion ECS Fargate"
3. Wybierz akcję: **START**
4. Opcjonalnie podaj subdomenę Serveo.net (pozostaw puste dla losowej)
5. Poczekaj na zakończenie workflow
6. URL bastionu pojawi się w GitHub Summary

### Połączenie z Bastionem

#### 1. Podstawowe SSH dostęp

Po uruchomieniu workflow **START**, otrzymasz URL w GitHub Summary:

```bash
# Bezpośrednie SSH do bastionu
ssh -p 80 ephemeral-bastion-abc123.serveo.net

# Jeśli port 80 jest zablokowany:
ssh -o ProxyCommand="curl -H @- http://ephemeral-bastion-abc123.serveo.net" %h
```

⚠️ **Ważne:** Bastion sam z siebie **nie da ci dostępu do żadnego serwera**. To jest tunel SSH - musisz mieć dostęp do wewnętrznych zasobów z innego miejsca (np. VPN, internal network, lub inny bastion).

#### 2. Port Forwarding - Dostęp do MySQL/PostgreSQL/itp.

Jeśli masz dostęp do bazy danych wewnątrz VPC (np. MySQL na `10.0.1.50:3306`):

**Wariant A - Forward lokalnie na port 3306:**
```bash
ssh -p 80 -L 3306:10.0.1.50:3306 ephemeral-bastion-abc123.serveo.net
```

Teraz połącz się lokalnie:
```bash
mysql -h localhost -u admin -p
# lub
psql -h localhost -U admin -d mydb
```

**Wariant B - Forward na inny port (np. 8306 - aby nie kolidować):**
```bash
ssh -p 80 -L 8306:10.0.1.50:3306 ephemeral-bastion-abc123.serveo.net
```

Teraz połącz się na innym porcie:
```bash
mysql -h localhost -P 8306 -u admin -p
```

**Wariant C - Forward z IP wewnętrznym (dostęp z innych komputerów w sieci):**
```bash
ssh -p 80 -L 0.0.0.0:3306:10.0.1.50:3306 ephemeral-bastion-abc123.serveo.net
```

Inne komputery w Twojej sieci mogą teraz łączyć się:
```bash
mysql -h 192.168.1.100 -u admin -p  # Twój IP w sieci
```

#### 3. Praktyczne przykłady

**Dostęp do Redis wewnątrz VPC:**
```bash
ssh -p 80 -L 6379:internal-redis.ec2.internal:6379 ephemeral-bastion-abc123.serveo.net
# Używaj: redis-cli -h localhost -p 6379
```

**Dostęp do RDS bazy danych:**
```bash
ssh -p 80 -L 5432:mydb.abcdefg.eu-central-1.rds.amazonaws.com:5432 ephemeral-bastion-abc123.serveo.net
# Używaj: psql -h localhost -U postgres -d mydb
```

**Dostęp do innego serwera SSH wewnątrz VPC:**
```bash
ssh -p 80 -L 2222:10.0.2.100:22 ephemeral-bastion-abc123.serveo.net
# Pierwsze SSH połączenie: wewnętrzny serwer
ssh -p 2222 localhost
```

#### 4. Jak to działa - przepływ dostępu

```
Twój komputer (localhost:3306)
           ↓ SSH-P 80
    Serveo.net tunel (publiczny)
           ↓
  ECS Fargate Task (private)
           ↓ SSH client w kontenerze
  Zasoby wewnątrz VPC (10.0.x.x)
```

Kroki:
1. Workflow **START** uruchamia task w Fargate
2. Task uruchamia SSH klienta, który łączy się z Serveo.net
3. Ty łączysz się do localhost:3306 (lub innego portu)
4. SSH tunel forwarduje ruch do IP/portu wewnątrz VPC
5. Task przesyła odpowiedź z powrotem przez Serveo.net do Ciebie

#### 5. Troubleshooting forwardowania

**Błąd: "Connection refused"**
```bash
# Sprawdź czy zarejestrowany IP:port istnieje wewnątrz VPC
ping 10.0.1.50
telnet 10.0.1.50 3306
```

**Błąd: "Address already in use" (port 3306 zajęty)**
```bash
# Użyj innego portu:
ssh -p 80 -L 8306:10.0.1.50:3306 ephemeral-bastion-abc123.serveo.net
```

**Port 80 zablokowany - użyj tunelu przez HTTP:**
```bash
ssh -p 80 -o ProxyCommand="curl -H @- http://ephemeral-bastion-abc123.serveo.net" \
    -L 3306:10.0.1.50:3306 %h
```

#### 6. Keep tunnel alive

SSH może się rozłączyć po nieaktywności. Aby utrzymać tunel:

```bash
ssh -p 80 \
    -L 3306:10.0.1.50:3306 \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -N \
    ephemeral-bastion-abc123.serveo.net
```

Opcje:
- `-N`: Nie wykonuj żadnego polecenia, tylko tunel
- `-o ServerAliveInterval=60`: Ping co 60 sekund
- `-o ServerAliveCountMax=3`: Rozłącz po 3 nieudanych ping'ach (3 minuty timeout)

### Zatrzymanie Bastionu (STOP)

1. Przejdź do GitHub Actions
2. Uruchom workflow "Efemeryczny Bastion ECS Fargate"
3. Wybierz akcję: **STOP**
4. Wszystkie zasoby zostaną usunięte

## Struktura Projektu

```
.
├── .github/
│   └── workflows/
│       └── deploy-bastion.yml    # GitHub Actions workflow
├── terraform/
│   ├── backend.tf                # Konfiguracja backendu
│   ├── main.tf                   # Główna konfiguracja zasobów
│   ├── variables.tf              # Zmienne wejściowe
│   └── outputs.tf                # Wyjścia Terraform
├── Dockerfile                    # Definicja kontenera z hardeningiem
├── start.sh                      # Skrypt startowy tunelu Serveo.net
└── README.md                     # Ten plik
```

### Zasoby Tworzone przez Terraform

Gdy uruchomisz workflow **START**:
- Tymczasowa podsieć w VPC
- Security Group (zablokowany inbound, SSH + DNS outbound)
- ECS Cluster
- ECS Task Definition
- ECS Fargate Task (z Twoim image'em)
- CloudWatch Log Group (1-dniowa retencja)
- IAM Role dla execution task

Gdy uruchomisz workflow **STOP**:
- Wszystkie powyższe zasoby są usuwane
- VPC pozostaje nienaruszone (będzie można go ponownie użyć)

## Troubleshooting

### Ogólne informacje

**Co robić jeśli task się uruchamia, ale nie mogę się połączyć?**

Typowy flow:
1. Task startuje w prywatnej sieci AWS (VPC)
2. Task uruchamia SSH klient, który tworzy tunel do Serveo.net
3. Ty łączysz się z Serveo.net (publiczny)
4. Ruch jest forwardowany przez tunel do zasobów w Twojej VPC

Jeśli coś nie działa, sprawdź każdy krok.

### Task nie uruchamia się
- Sprawdź czy VPC_ID jest poprawne
- Sprawdź czy rola IAM ma odpowiednie uprawnienia
- Sprawdź czy container_image URI jest prawidłowy (ECR lub public)
- Sprawdź CloudWatch Logs pod kątem błędów

### Błąd: "Unable to pull image"
- Sprawdź czy image jest dostępny w GitHub Container Registry
- Workflow automatycznie pushuje image - sprawdź GitHub Actions logs
- Jeśli używasz prywatnego ECR: sprawdź IAM permissions dla ECS Task Role

### Serveo.net nie działa
- Sprawdź czy podsieć ma public IP
- Sprawdź czy Security Group pozwala na outbound SSH (port 22)
- Sprawdź czy kontener ma dostęp do internetu (DNS resolution)
- Sprawdź CloudWatch logs: "Inicjalizacja tunelu Serveo.net"

### Terraform apply kończy się błędem
- Sprawdź czy podsieć CIDR nie koliduje z istniejącymi
- Uruchom STOP przed ponownym START
- Sprawdź czy zmienne Terraform przeszły walidację

### Koszty ECR są za wysokie
- Workflow używa GitHub Container Registry (GHCR) - bezpłatny!
- Jeśli chcesz zmienić na AWS ECR: zmień workflow i ustaw lifecycle policy do auto-cleanup

## Licencja

LICENSE
