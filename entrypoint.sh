#!/bin/sh

chown -R root:named /etc/bind /var/cache/bind /var/run/named
chmod -R 770 /var/cache/bind /var/run/named
chmod -R 750 /etc/bind

# generate rndc config, if not exists
if [[ ! -f /etc/letsencrypt/credentials.ini ]]; then
    rndc-confgen -A hmac-sha512 -b 512 -r /dev/urandom -k acme -a
    mykey=$(cat /etc/bind/rndc.key | grep secret | sed -r 's/(\s+)secret \"(.*)\";$/\2/g')
    echo "\
dns_rfc2136_server = 127.0.0.1
dns_rfc2136_port = 953
dns_rfc2136_name = acme
dns_rfc2136_secret = $mykey
dns_rfc2136_algorithm = HMAC-SHA512" > /etc/letsencrypt/credentials.ini
    chmod 0600 /etc/letsencrypt/credentials.ini
    
    echo "\
include \"/etc/bind/rndc.key\";
controls {
    inet 127.0.0.1 port 953
    allow { localhost; } keys { \"acme\"; };
};" > /etc/bind/acme.conf

    if [ -z $(grep -Fx 'include "/etc/bind/acme.conf";' /etc/bind/named.conf) ]; then
        sed -i '/options/i\include "/etc/bind/acme.conf";' /etc/bind/named.conf
    fi
fi

exec /usr/sbin/named -c /etc/bind/named.conf -g -u named

# Initial certificate request, but skip if cached
if [[ "${DOMAIN}" != "server.tld" ]]; then
    if [ ! -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ]; then
        certbot certonly --dns-rfc2136 \
        --dns-rfc2136-credentials /etc/letsencrypt/credentials.ini \
        --preferred-challenges dns-01 \
        --server https://acme-v02.api.letsencrypt.org/directory \
        --email "${EMAIL}" \
        -d ${DOMAIN} \
        --agree-tos

        cd /etc/letsencrypt
        ln -s live/${DOMAIN}/cert.pem cert.pem
        ln -s live/${DOMAIN}/chain.pem chain.pem
        ln -s live/${DOMAIN}/fullchain.pem fullchain.pem
        ln -s live/${DOMAIN}/privkey.pem privkey.pem  
   else
      certbot renew
   fi
fi

if [ ! -z "$@" ]; then
    extra="$@"
    for d in $extra
    do
        certbot certonly --dns-rfc2136 \
        --dns-rfc2136-credentials /etc/letsencrypt/credentials.ini \
        --preferred-challenges dns-01 \
        --server https://acme-v02.api.letsencrypt.org/directory \
        --dns-rfc2136-propagation-seconds 30 \
        --email "${EMAIL}" \
        -d ${d} \
        --agree-tos
    done
fi
