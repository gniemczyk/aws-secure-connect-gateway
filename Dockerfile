# Minimalny obraz bazowy Alpine Linux
FROM public.ecr.aws/docker/library/alpine:3.19

# Instalacja tylko SSH klienta na etapie budowania
# Po tej fazie nie będzie możliwości instalacji dodatkowych pakietów
RUN apk add --no-cache openssh-client && \
    apk cache clean

# Kopiowanie skryptu startowego
COPY start.sh /usr/local/bin/start.sh

# Nadanie uprawnień wykonywania dla 'nobody' user
# UID 65534 to standardowy 'nobody' user w Alpine (już istnieje)
RUN chmod 500 /usr/local/bin/start.sh && \
    chown nobody:nobody /usr/local/bin/start.sh

# Usunięcie niepotrzebnych plików i katalogów dla minimalizacji ataku powierzchni
RUN rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Przełączenie na użytkownika non-root (nobody - UID 65534)
USER nobody

# Ustawienie katalogu roboczego
WORKDIR /home/nobody

# Otwarcie portu 22 (tylko informacyjne, kontener nie nasłuchuje)
EXPOSE 22

# Uruchomienie skryptu startowego
ENTRYPOINT ["/usr/local/bin/start.sh"]
