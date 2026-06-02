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

```bash
# Użyj portu 80 (HTTP) dla tunelu Serveo.net
ssh -p 80 twoja-subdomena.serveo.net

# Alternatywnie, jeśli port 80 jest zablokowany, użyj:
ssh -o ProxyCommand="curl -H @- http://twoja-subdomena.serveo.net" %h
```

**Przykład z rzeczywistą subdomą:**
```bash
ssh -p 80 ephemeral-bastion-abc123.serveo.net
```

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
