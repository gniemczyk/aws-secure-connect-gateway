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
- **Security Group**: Tylko outbound (inbound całkowicie zablokowany)
- **Public IP**: Tylko dla połączenia z Serveo.net

## Wymagania Wstępne

### GitHub Variables
Ustaw w repozytorium GitHub (Settings → Secrets and variables → Actions → Variables):
- `VPC_ID`: ID istniejącego VPC w trybie Dual-Stack

### GitHub Secrets
Ustaw w repozytorium GitHub (Settings → Secrets and variables → Actions → Secrets):
- `AWS_ROLE_ARN`: ARN roli IAM dla OIDC (np. `arn:aws:iam::123456789012:role/github-actions-role`)

### Konfiguracja OIDC w AWS

1. **Utwórz Identity Provider w AWS IAM Console**:
   - Provider type: OpenID Connect
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **Utwócz Rolę IAM**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
           }
         }
       }
     ]
   }
   ```

3. **Dodaj uprawnienia do roli**:
   - AdministratorAccess (lub ograniczone do ECS, VPC, ECR, CloudWatch)

4. **Skopiuj ARN roli** i ustaw jako `AWS_ROLE_ARN` w GitHub Secrets

### Amazon ECR Repository

Utwórz prywatne repozytorium ECR o nazwie `bastion` w regionie `eu-central-1`.

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
ssh https://twoja-subdomena.serveo.net
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

## Zasoby Tworzone przez Terraform

### START
- Tymczasowa podsieć w VPC
- Security Group (zablokowany inbound, otwarty outbound)
- ECS Cluster
- ECS Task Definition (z readonlyRootFilesystem)
- ECS Fargate Task
- CloudWatch Log Group
- IAM Role dla execution task

### STOP
- Wszystkie powyższe zasoby są usuwane
- VPC pozostaje nienaruszone

## Troubleshooting

### Task nie uruchamia się
- Sprawdź czy VPC_ID jest poprawne
- Sprawdź czy rola IAM ma odpowiednie uprawnienia
- Sprawdź CloudWatch Logs pod kątem błędów

### Serveo.net nie działa
- Sprawdź czy podsieć ma public IP
- Sprawdź czy Security Group pozwala na outbound
- Sprawdź czy kontener ma dostęp do internetu

### Terraform apply kończy się błędem
- Sprawdź czy podsieć CIDR nie koliduje z istniejącymi
- Uruchom STOP przed ponownym START

## Licencja

LICENSE
