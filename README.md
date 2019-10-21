# Installation

ZABBIX_CONFDIR=/usr/local/etc/zabbix4 below

1. Copy freebsd-release-stats.sh to $ZABBIX_CONFDIR/scripts/
(create directory if necessary)

2. Copy userparameter_freebsd_release.conf to $ZABBIX_CONFDIR/zabbix_agentd.conf.d/

3. Create /var/db/zabbix directory, owned by zabbix:zabbix

4. Import Zabbix template zabbix-freebsd-release.xml and assign to the FreeBSD host

   You may need to change the type of freebsd.release.stats item to "Zabbix agent" (configured as "Zabbix agent (active)" in the template.
