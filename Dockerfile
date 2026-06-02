# Minimalny obraz bazowy Alpine Linux
FROM public.ecr.aws/docker/library/alpine:3.19

# Instalacja tylko SSH klienta na etapie budowania
# Po tej fazie nie będzie możliwości instalacji dodatkowych pakietów
RUN apk add --no-cache openssh-client && \
    apk cache clean

# Tworzenie użytkownika bez uprzywilejowanych uprawnień (non-root)
# UID 65534 to typowy 'nobody' user
RUN addgroup -g 65534 bastion && \
    adduser -D -u 65534 -G bastion -s /bin/sh bastion

# Kopiowanie skryptu startowego
COPY start.sh /usr/local/bin/start.sh

# Nadanie uprawnień wykonywania tylko dla właściciela
RUN chmod 500 /usr/local/bin/start.sh && \
    chown bastion:bastion /usr/local/bin/start.sh

# Usunięcie niepotrzebnych plików i katalogów dla minimalizacji ataku powierzchni
RUN rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Przełączenie na użytkownika non-root
USER bastion

# Ustawienie katalogu roboczego
WORKDIR /home/bastion

# Otwarcie portu 22 (tylko informacyjne, kontener nie nasłuchuje)
EXPOSE 22

# Uruchomienie skryptu startowego
ENTRYPOINT ["/usr/local/bin/start.sh"]
