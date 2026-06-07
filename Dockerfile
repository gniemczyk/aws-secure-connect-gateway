# Minimalny obraz bazowy Alpine Linux
FROM public.ecr.aws/docker/library/alpine:3.19

# Instalacja openssh (klient + serwer) na etapie budowania
RUN apk add --no-cache openssh-client openssh-server && \
    rm -rf /var/cache/apk/*

# Przygotowanie katalogów dla sshd
RUN mkdir -p /etc/ssh /run/sshd /root/.ssh && \
    chmod 700 /root/.ssh

# Konfiguracja sshd - efemeryczny bastion (bezpieczeństwo = krótki czas życia + losowa subdomena)
RUN echo "Port 22" > /etc/ssh/sshd_config && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config && \
    echo "X11Forwarding no" >> /etc/ssh/sshd_config && \
    echo "PrintMotd yes" >> /etc/ssh/sshd_config && \
    echo "AcceptEnv LANG LC_*" >> /etc/ssh/sshd_config && \
    echo "Subsystem sftp /usr/lib/ssh/sftp-server" >> /etc/ssh/sshd_config && \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config && \
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config && \
    echo "MaxAuthTries 5" >> /etc/ssh/sshd_config && \
    echo "LoginGraceTime 60" >> /etc/ssh/sshd_config && \
    echo "MaxSessions 3" >> /etc/ssh/sshd_config

# Ustawienie pustego hasla root (login bez hasla)
RUN passwd -d root

# Kopiowanie skryptu startowego
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

# Usunięcie niepotrzebnych plików dla minimalizacji powierzchni ataku
RUN rm -rf /tmp/* /var/tmp/*

# Ustawienie katalogu roboczego
WORKDIR /root

# Port 22 - sshd nasłuchuje (dostępny przez tunel Serveo)
EXPOSE 22

# Uruchomienie skryptu startowego
ENTRYPOINT ["/usr/local/bin/start.sh"]
