#!/bin/sh
FREEBSD_UPDATE_CONF="/etc/freebsd-update.conf"
PUB_SSL="/var/db/zabbix/freebsd-update-pub.ssl"
ZABBIX_AGENTD_CONF="`dirname $0`/../zabbix_agentd.conf"

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
	if [ ! -f "$PUB_SSL" ]; then
		fetch -o "$PUB_SSL" "$base_url/pub.ssl" || return # try next update server
	fi

	# check public key signature
	sig=`sha256 $PUB_SSL | sed 's/.*= //'`
	[ x"$sig" == x"$KEYPRINT" ] || die "$PUB_SSL: Invalid signature"

	# fetch latest update meta
	meta=`fetch -q -o - "$base_url/latest.ssl" | openssl rsautl -pubin -inkey $PUB_SSL -verify | sed 's/|/ /g'` || return # try next update server
	set -- $meta
	rel="$3"
	patchlevel="$4"
	eol="$6"

	relp=`uname -r | sed -e 's,.*-,,' -e 's/^p//'`
	available_update=
	if [ $patchlevel -gt $relp ]; then
		available_update="$rel-p$patchlevel"
	fi
	echo "$HOSTNAME freebsd.release.update $TIMESTAMP \"$available_update\""
	echo "$HOSTNAME freebsd.release.eol $TIMESTAMP $eol"
	exit 0
}

zabbix_send()
{
	data="$1"

	result=$(echo "$data" | zabbix_sender -c $ZABBIX_AGENTD_CONF -v -T -i - 2>&1)
	response=$(echo "$result" | awk -F ';' '$1 ~ /^info/ && match($1,/[0-9].*$/) {sum+=substr($1,RSTART,RLENGTH)} END {print sum}')
	if [ -n "$response" ]; then
		echo "$response"
	else
		echo "$result"
	fi
}

HOSTNAME="`hostname`"
TIMESTAMP=`date "+%s"`
KEYPRINT=`get_conf KeyPrint`
servername=`get_conf ServerName`
rel=`uname -r | sed -E -e 's,-p[0-9]+,,' -e 's,-SECURITY,-RELEASE,'`
arch=`uname -m`

for s in `get_servers $servername`; do
	base_url="http://$s/${rel}/${arch}"
	data=`check_update $base_url`
	if [ -z "$data" ]; then
		continue # next server
	fi

	if [ -n "$DEBUG" ]; then
		echo "$data"
	else
		zabbix_send "$data"
	fi
	break
done
