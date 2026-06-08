# Minimalny obraz bazowy Alpine Linux
FROM public.ecr.aws/docker/library/alpine:3.19

# Instalacja przydatnych narzedzi dla bastionu
RUN apk add --no-cache \
    bash \
    curl \
    bind-tools \
    openssh-client \
    nmap-ncat \
    jq \
    socat \
    postgresql-client \
    mysql-client \
    redis \
    aws-cli \
    openssl \
    vim \
    nano \
    net-tools \
    iproute2 \
    tcpdump \
    && rm -rf /var/cache/apk/*

# Kopiowanie skryptu startowego
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

WORKDIR /root

ENTRYPOINT ["/usr/local/bin/start.sh"]
