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

2. **Utwórz Rolę IAM** (Least Privilege - branch-restricted):
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
           "StringLike": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
             "token.actions.githubusercontent.com:sub": [
               "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
               "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/develop",
               "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/test"
             ]
           }
         }
       }
     ]
   }
   ```
   
   **Uwaga:** Ta polityka ogranicza dostęp tylko do wybranych gałęzi (main, develop, test).
   Dla bardziej permisywnego dostępu ze wszystkich gałęzi, zastosuj:
   ```json
   "Condition": {
     "StringLike": {
       "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
       "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
     }
   }
   ```

3. **Dodaj uprawnienia do roli**:
   - AdministratorAccess (lub ograniczone do ECS, VPC, ECR, CloudWatch)

4. **Skopiuj ARN roli** i ustaw jako `AWS_ROLE_ARN` w GitHub Secrets

### Amazon ECR Repository - Opcje Konfiguracji

**Opcja 1: Minimalna (Rekomendowana dla ephemerycznych deploymentów) ✅**

Nie twórz prywatnego ECR. Zamiast tego:
- GitHub Actions builduje image na locie
- Pushuje do publicznego ECR (AWS managed images)
- Image się nie przechowuje (maksymalnie cache GitHub Actions)
- Brak kosztów przechowywania
- Szybkie deployuję

Konfiguracja: Zmień `container_image` w GitHub Actions na:
```bash
# Public AWS ECR (Alpine + openssh-client)
public.ecr.aws/alpine:latest
```

---

**Opcja 2: Prywatne ECR z retencją (Jeśli chcesz cache'ować)**

Utwórz prywatne repozytorium ECR:
```bash
aws ecr create-repository \
  --repository-name bastion \
  --region eu-central-1 \
  --encryption-configuration encryptionType=AES
```

**Ustaw lifecycle policy (auto-cleanup po 1 dniu):**
```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Usuń image'y starsze niż 1 dzień",
      "selection": {
        "tagStatus": "any",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

Zastosuj policy:
```bash
aws ecr put-lifecycle-policy \
  --repository-name bastion \
  --lifecycle-policy-text file://lifecycle-policy.json
```

---

**Opcja 3: Hybrid (Optymalna dla produkcji) ✨**

- Builduj image w Fargate (nie w GitHub Actions)
- Nie przechowuj w ECR
- Każdy deployment = fresh build
- Brak kosztów przechowywania
- Maksymalna bezpieczność (no stale images)

Ta opcja wymaga modyfikacji workflow (będzie dostępna w przyszłości)

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

## Zasoby Tworzone przez Terraform

### START
- Tymczasowa podsieć w VPC
- Security Group (zablokowany inbound, tylko SSH + DNS outbound)
- ECS Cluster
- ECS Task Definition (z readonlyRootFilesystem)
- ECS Fargate Task
- CloudWatch Log Group (1-dniowa retencja)
- IAM Role dla execution task

### STOP
- Wszystkie powyższe zasoby są usuwane
- VPC pozostaje nienaruszone
- ECR image (jeśli był) pozostaje (użyj lifecycle policy do auto-cleanup)

## Troubleshooting

### Task nie uruchamia się
- Sprawdź czy VPC_ID jest poprawne
- Sprawdź czy rola IAM ma odpowiednie uprawnienia
- Sprawdź czy container_image URI jest prawidłowy (ECR lub public)
- Sprawdź CloudWatch Logs pod kątem błędów

### Błąd: "Unable to pull image"
- Jeśli używasz private ECR: sprawdź uprawnienia IAM dla ECS Task
- Jeśli używasz public ECR: sprawdź dostęp do internetu z Fargate
- Sprawdź czy image tag istnieje w repozytorium

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
- Użyj Opcji 1 (public ECR, nie przechowuj image'ów)
- Lub ustaw lifecycle policy do auto-cleanup na Opcji 2
- Lub wdrażaj Opcję 3 (hybrid model)

## Licencja

LICENSE
