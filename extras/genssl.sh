#!/bin/sh
prefix="`pwd`"
exec_prefix="${prefix}"
sysconfdir="${prefix}"

echo "Generating self-signed certificate .. "
openssl req -x509 -nodes -newkey rsa:2048 -keyout "${sysconfdir}"/ssl.key -out "${sysconfdir}"/ssl.cert

echo "Generating Diffie-Hellman file for secure SSL/TLS negotiation .. "
openssl dhparam -out "${sysconfdir}"/dh.pem 2048

# If sysconfdir is relative to prefix, make the path relative. I.e.,
# prefix=/usr and sysconfdir=/etc -> relative_sysconfdir=/etc,
# prefix=/home/binki/chary and sysconfdir=/home/binki/chary/etc ->
# relative_sysconfdir=etc
relative_sysconfdir="${sysconfdir#${prefix%/}/}"
relative_sysconfdir="${relative_sysconfdir%/}"

