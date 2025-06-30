#!/bin/sh
FREEBSD_UPDATE_CONF="/etc/freebsd-update.conf"
FREEBSD_UPDATE_PUB_SSL="${FREEBSD_UPDATE_PUB_SSL:-/var/db/zabbix/freebsd-update-pub.ssl}"

set -o pipefail

die()
{
	echo 1>&2 "$@"
	exit 1
}

get_conf()
{
	key="$1"

	(grep -o "^[[:space:]]*$key[[:space:]]*\([^[:space:]]*\)" $FREEBSD_UPDATE_CONF || die "Failed to find $key in $FREEBSD_UPDATE_CONF") |
		sed 's/.*[[:space:]]//'
}

get_servers()
{
	name="_http._tcp.$1"

	host -t srv "$name" |
		sed -nE "s/$name (has SRV record|server selection) //I; s/\.$//; p" |
		sort -n -k 1 |
		cut -f 4 -d ' ' |
		sort -R
}

check_update()
{
	base_url="$1"

	# fetch public key if not exists locally
	if [ ! -f "$FREEBSD_UPDATE_PUB_SSL" ]; then
		fetch -q -o "$FREEBSD_UPDATE_PUB_SSL" "$base_url/pub.ssl" || return # try next update server
	fi

	# check public key signature
	sig=`sha256 $FREEBSD_UPDATE_PUB_SSL | sed 's/.*= //'`
	[ x"$sig" == x"$KEYPRINT" ] || die "$FREEBSD_UPDATE_PUB_SSL: Invalid signature"

	# fetch latest update meta
	meta=`fetch -q -o - "$base_url/latest.ssl" | $OPENSSL_VERIFY | sed 's/|/ /g'` || return # try next update server
	set -- $meta
	rel="$3"
	patchlevel="$4"
	eol="$6"

	cat << EOF
{
    "running": "`freebsd-version`",
    "latest": "$rel-p$patchlevel",
    "eol": $eol
}
EOF
	exit 0
}

KEYPRINT=`get_conf KeyPrint`
servername=`get_conf ServerName`
rel=`freebsd-version | sed -E -e 's,-p[0-9]+,,' -e 's,-SECURITY,-RELEASE,'`
arch=`uname -m`

openssl_major_ver=$(openssl version | awk '{ print $2 }' | sed 's/\..*//')
if [ "$openssl_major_ver" -ge 3 ]; then
	OPENSSL_VERIFY="openssl pkeyutl -pubin -inkey $FREEBSD_UPDATE_PUB_SSL -verifyrecover"
else
	OPENSSL_VERIFY="openssl rsautl -pubin -inkey $FREEBSD_UPDATE_PUB_SSL -verify"
fi

for s in `get_servers $servername`; do
	base_url="http://$s/${rel}/${arch}"
	check_update $base_url
done
