# Minimalny obraz bazowy Alpine Linux
FROM public.ecr.aws/docker/library/alpine:3.19

# Tylko bash - resztę instalujesz na żądanie po połączeniu
# Przykładowe komendy instalacji:
#   apk add curl jq aws-cli
#   apk add postgresql-client mysql-client redis
#   apk add nmap-ncat socat tcpdump
RUN apk add --no-cache bash && \
    rm -rf /var/cache/apk/*

# Kopiowanie skryptu startowego
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

WORKDIR /root

ENTRYPOINT ["/usr/local/bin/start.sh"]
