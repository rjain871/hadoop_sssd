#!/bin/bash

"""
Author : Rishi Jain
"""


if [ "$(whoami)" != "root" ]
then
	"run me as root or via sudo"
	exit
fi



# prepping some vars
hostname=$(hostname)
upperhostname=$(echo $hostname | tr '[a-z]' '[A-Z]')
export LC_ALL="en_US.UTF-8"


# installing depandancies
yum -y install sssd oddjob-mkhomedir authconfig sssd-krb5 sssd-ad sssd-tools
yum -y -q install adcli
yum -y -q install dbus

# backing up configs
cp /etc/krb5.conf /etc/krb5.conf.orig


#configure AD CA certificate

openssl s_client -connect ad-21115.lab.hortonworks.net:636 <<<'' | openssl x509 -out ad-ca.cer
cp ad-ca.cer /etc/pki/ca-trust/source/anchors/ad-ca.cer
sudo update-ca-trust force-enable
sudo update-ca-trust extract
sudo update-ca-trust check



##-------------------------------------------------------------------------------------------------------------------------
# writing ldap.conf
cat << 'EOF' > /etc/openldap/ldap.conf
TLS_CACERT /etc/pki/tls/cert.pem
URI ldaps://ad-21115.lab.hortonworks.net ldap://ad-21115.lab.hortonworks.net
BASE dc=lab,dc=hortonworks,dc=net
EOF

##-------------------------------------------------------------------------------------------------------------------------
# writing hosts file
echo "172.26.66.112 ad-21115.lab.hortonworks.net ad-21115" >> /etc/hosts



##-------------------------------------------------------------------------------------------------------------------------
# writing krb5.conf

sed -i '/\[realms\]/a LAB.HORTONWORKS.NET = {\n kdc = ad-21115.lab.hortonworks.net \n admin_server = ad-21115.lab.hortonworks.net \n }\n' /etc/krb5.conf

##-------------------------------------------------------------------------------------------------------------------------


# writing sssd.conf
ad_user="registersssd@LAB.HORTONWORKS.NET"
ad_domain="lab.hortonworks.net"
ad_dc="ad-21115.lab.hortonworks.net"
ad_root="dc=lab,dc=hortonworks,dc=net"
ad_realm=${ad_domain^^}
ad_ou="ou=HadoopNodes,${ad_root}"

echo "Please enter the password BadPass#1"

kinit ${ad_user}

sudo adcli join -v \
  --domain-controller=${ad_dc} \
  --domain-ou="${ad_ou}" \
  --login-ccache="/tmp/krb5cc_0" \
  --login-user="${ad_user}" \
  -v \
  --show-details


cat <<EOF > /etc/sssd/sssd.conf
[sssd]
## master & data nodes only require nss. Edge nodes require pam.
services = nss, pam, ssh, autofs, pac
config_file_version = 2
domains = ${ad_realm}
override_space = _

[domain/${ad_realm}]
id_provider = ad
ad_server = ${ad_dc}
#ad_server = ad01, ad02, ad03
#ad_backup_server = ad-backup01, 02, 03
auth_provider = ad
chpass_provider = ad
access_provider = ad
enumerate = False
krb5_realm = ${ad_realm}
ldap_schema = ad
ldap_id_mapping = True
cache_credentials = True
ldap_access_order = expire
ldap_account_expire_policy = ad
ldap_force_upper_case_realm = true
fallback_homedir = /home/%d/%u
default_shell = /bin/false
ldap_referrals = false

[nss]
memcache_timeout = 3600
override_shell = /bin/bash

EOF


##-------------------------------------------------------------------------------------------------------------------------

sudo chmod 0600 /etc/sssd/sssd.conf
sudo service sssd restart
sudo authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablelocauthorize --update
sudo messagebus restart
sudo chkconfig messagebus on
sudo chkconfig oddjobd on
sudo service oddjobd restart
sudo chkconfig sssd on
sudo service sssd restart
##-------------------------------------------------------------------------------------------------------------------------

clear
echo "config done"
