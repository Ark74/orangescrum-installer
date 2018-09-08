#!/bin/bash
# OrangeScrum Installer PHP 7.2 / MariaDB
# *buntu 16.04 (LTS)
# SwITNet Ltd © - 2018, https://switnet.net/
# GNU GPLv3 or later.

# Check correct user (no root)
clear
if [ "$EUID" == 0 ]
  then echo "Ok, you have superuser powers"
else
	echo "You should run it with root or sudo permissions."
	exit
fi

echo "
#=================================================================
So far this scripts only can set SendGrid smtp mail gateway,
for other services, please configure them manually.

Also this script so far is intended to be executed on a clean instance.
#=================================================================
"

PHP_VERSION=$(apt-cache show php | grep Version | head -n 1 | cut -d ":" -f3 | cut -d "+" -f 1)
PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
SHUF=$(shuf -i 13-19 -n 1)
MARIADB_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
PW_FILE=/var/mysql_password.txt
echo "$MARIADB_PASS" > $PW_FILE
chmod 600 $PW_FILE
chown root:root $PW_FILE
OS_USER=orangesm
USERDB_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
USERDB_PW=/var/userdb_password.txt
echo "$USERDB_PASS" > $USERDB_PW
chmod 600 $USERDB_PW
chown root:root $USERDB_PW
PHPMYADMIN_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
PHPMA_PW_FILE=/var/phpmyadmin_password.txt
echo "$PHPMYADMIN_PASS" > $PHPMA_PW_FILE
chmod 600 $PHPMA_PW_FILE
chown root:root $PHPMA_PW_FILE
APPROOT=/var/www/html/orangescrum
CONF_FILE=orangescrum.conf
HTTPS_CONF=/etc/apache2/sites-available/$CONF_FILE
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
DISTRO_RELEASE=$(lsb_release -sc)
if [ $DISTRO_RELEASE = flidas ]; then
DISTRO_RELEASE="xenial"
fi
UNIV=$(apt-cache policy | grep http | awk '{print $3}' | grep universe | head -n 1 | cut -d "/" -f 2)

echo "Pease set your (sub)domain example: demo.domain.com"
read -p "sub/domain: " OSDOMAIN

if [ "$DISTRO_RELEASE" != "xenial" || "$PHP_VERSION" != "7.0" ]
then
echo "
#=================================================================
At the time of coding the PHP7 version of OrangeScrum only supports PHP 7.0.
Your system PHP version is not supported.
#=================================================================
"
	exit
fi

echo -n 'Do you wanna setup Sendgrid automatically? (yes or no): '
while [[ $sga != yes && $sga != no ]]
do
	read sga
if [ $sga = no ]; then
	echo "Ok, sedgrid won't be setup, you'll need to edit manually later."
elif [ $sga = yes ]; then
	echo "Let's get to it ..."
	read -p "SendGrid username: " SMTP_UNAME
	read -p "Sendgrid password: " -sr SMTP_PWORD
fi
done

echo ''
echo -n 'Do you wanna remove the Google Group footer? (yes or no): '
while [[ $rgg != yes && $rgg != no ]]
do
	read rgg
if [ $rgg = no ]; then
	echo "Ok, it will be kept.
	"
elif [ $rgg = yes ]; then
	echo "Ok, it will be removed.
	"
fi
done

apt update -qq

check_universe() {
if [ "$UNIV" = "universe" ]
then
        echo "Seems that required repositories are ok."
else
        echo "Adding required repo (universe)."
        add-apt-repository universe
fi
}

install_mcrypt() {
if [ $PHP_VERSION == 7.2 ]; then
	echo "Building mcrypt"
	apt-get -y install php-pear php7.2-dev gcc make autoconf libc-dev pkg-config libmcrypt-dev
	printf "\n" | pecl install mcrypt-1.0.1
	echo "extension=/usr/lib/php/20170718/mcrypt.so" > /etc/php/$PHP_VERSION/cli/conf.d/mcrypt.ini
	echo "extension=/usr/lib/php/20170718/mcrypt.so" > /etc/php/$PHP_VERSION/apache2/conf.d/mcrypt.ini
	service php7.2-fpm restart
	service apache2 restart
	php --ri mcrypt
elif [ $PHP_VERSION == 7.0 ]; then
	apt install -y php-mcrypt
else
	echo "You're not running a supported PHP version for this script, exiting..."
	exit
fi
}

install_mariadb() {
	if [ "$(dpkg-query -W -f='${Status}' "mariadb-server" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
		echo "MariaDB already installed"
	else
		echo "# Installing MariaDB"
		apt install software-properties-common -y
		apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
		add-apt-repository "deb [arch=amd64] http://ftp.ddg.lth.se/mariadb/repo/10.3/ubuntu $DISTRO_RELEASE main"
		debconf-set-selections <<< "mariadb-server-10.3 mysql-server/root_password password $MARIADB_PASS"
		debconf-set-selections <<< "mariadb-server-10.3 mysql-server/root_password_again password $MARIADB_PASS"
		apt update -qq
		apt install -y mariadb-server-10.3
	fi
}

secure_mariadb() {
apt -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root:\"
send \"$MARIADB_PASS\r\"
expect \"Would you like to setup VALIDATE PASSWORD plugin?\"
send \"n\r\"
expect \"Change the password for root ?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"
apt remove -y expect
}

disable_gmail() {
sed -i "s|//Gmail SMTP|/* //Gmail SMTP|" $APPROOT/app/Config/constants.php
sed -i "s|(Get the list of Host names)|(Get the list of Host names) */|" $APPROOT/app/Config/constants.php
}

set_email_domain() {
sed -i "s|YourDomain.com|$OSDOMAIN|g" $APPROOT/app/Config/constants.php
sed -i "s|'notify@mycompany.com'|"\'notify@$OSDOMAIN\'"|g" $APPROOT/app/Config/constants.php
sed -i "s|'support@mycompany.com'|"\'support@$OSDOMAIN\'"|g" $APPROOT/app/Config/constants.php
sed -i "s|'developer@mycompany.com'|"\'webmaster@$OSDOMAIN\'"|g" $APPROOT/app/Config/constants.php
sed -i "s|www.my-orangescrum.com/|$OSDOMAIN/|g" $APPROOT/app/Config/constants.php
}

set_sengrid() {
	if [ $sga = yes ]; then
		sed -i "s|//Sendgrid smtp|//Sendgrid smtp */|" $APPROOT/app/Config/constants.php
		sed -i "s|//https://sendgrid.com/user/signup (free signup to sendgrid)|/* https://sendgrid.com/user/signup (free signup to sendgrid)|" $APPROOT/app/Config/constants.php
		sed -i "34,45{s|youremail@domain.com|$SMTP_UNAME|}" $APPROOT/app/Config/constants.php
		sed -i "34,45{s|\*\*\*\*\*\*|$SMTP_PWORD|}" $APPROOT/app/Config/constants.php
	else
		echo "Please remmember to set up your smtp gateway at $APPROOT/app/Config/constants.php"
	fi
}

remove_google_group() {
		if [ $rgg = yes ]; then
			echo "# Customize - Remove Google Group"
			sed -i "s|Orangescrum's Google Group</a>.|Orangescrum's Google Group</a>. -->|" /var/www/html/orangescrum/app/View/Users/login.ctp
			sed -i 's|<a href="https://groups.google.com|<!-- <a href="https://groups.google.com|' /var/www/html/orangescrum/app/View/Elements/footer_inner.ctp
			sed -i 's|<a href="https://groups.google.com|<!-- <a href="https://groups.google.com|' /var/www/html/orangescrum/app/View/Users/login.ctp
			sed -i "s|Orangescrum's Google Group</a>.|Orangescrum's Google Group</a>. -->|" /var/www/html/orangescrum/app/View/Elements/footer_inner.ctp
		else 
			echo "Google Groups footer remains"
		fi
}

# System requirements
check_universe
apt update -qq
apt install -yf git htop unzip
echo "# Install App requirements"
apt install -yf apache2 \
				libapache2-mod-php \
				php \
				php-cli \
				php-curl \
				php-dba \
				php-fpm \
				php-gd \
				php-gettext \
				php-imap \
				php-intl \
				php-ldap \
				php-mbstring \
				php-mcrypt \
				php-mysql \
				php-snmp \
				php-soap \
				php-tidy \
				php-xml \
				php-xmlrpc \
				php-zip
				
#install_mcrypt

a2enmod rewrite headers

# Change values in php.ini (increase max file size)
# max_execution_time
sed -i "s|max_execution_time =.*|max_execution_time = 3500|g" $PHP_INI
# max_input_time
sed -i "s|max_input_time =.*|max_input_time = 3600|g" $PHP_INI
# memory_limit
sed -i "s|memory_limit =.*|memory_limit = 512M|g" $PHP_INI
# post_max
sed -i "s|post_max_size =.*|post_max_size = 600M|g" $PHP_INI
# upload_max
sed -i "s|upload_max_filesize =.*|upload_max_filesize = 500M|g" $PHP_INI

install_mariadb
secure_mariadb

echo '[mysqld]
sql_mode="IGNORE_SPACE,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"' > /etc/mysql/conf.d/disable_strict_mode.cnf
service mysql restart

mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET plugin='' WHERE user='root';"
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET password=PASSWORD('$MARIADB_PASS') WHERE user='root';"
mysql -u root -p"$MARIADB_PASS" -e "FLUSH PRIVILEGES;"

mysql -u root -p"$MARIADB_PASS"<<QUERY
CREATE USER '${OS_USER}'@'localhost' IDENTIFIED BY '${USERDB_PASS}';
CREATE DATABASE orangescrum CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON orangescrum.* to '${OS_USER}'@'localhost' IDENTIFIED BY '${USERDB_PASS}';
FLUSH PRIVILEGES;
QUERY

#--------------------------------------------------
echo "# Install Node less"
#--------------------------------------------------
if [ "$(dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -c "ok")" == "1" ]; then
	echo "Nodejs is installed, skipping..."
else
	curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
	apt install -y nodejs
	npm install -g less less-plugin-clean-css
fi

#--------------------------------------------------
echo " # Install wkhtmltopdf"
#--------------------------------------------------
if [ -f /usr/bin/wkhtmltopdf ]; then
	echo -e "\n---- wkhtmltopdf already installed! ----"
	wkhtmltopdf -V
else
	echo -e "\n---- Install wkhtml for OrangeScrub ----"
	apt install -y --no-install-recommends wkhtmltopdf
fi

cd /var/www/html
git clone --depth 1 -b orangescrum-master-php7 https://github.com/orangescrum/orangescrum
chown -R www-data:www-data $APPROOT

echo "# Install DB"
mysql -u $OS_USER -p"$USERDB_PASS" orangescrum < $APPROOT/database.sql
rm -rf $APPROOT/database.sql
chmod -R 0777 $APPROOT/app/tmp


echo "# Set PHP Config files"
# -> database.php
sed -i "s|'login' => 'root',|'login' => "\'$OS_USER\'",|g" $APPROOT/app/Config/database.php
sed -i "s|'password' => '',|'password' => "\'$USERDB_PASS\'",|g" $APPROOT/app/Config/database.php
sed -i "s|'database' => 'orangescrum',|'database' => 'orangescrum',|g" $APPROOT/app/Config/database.php

# -> constants.php
echo "# Change Email Parameters"
disable_gmail
set_email_domain
set_sengrid
remove_google_group
## L O C A L  F I X E S ##
# Note on hardcoded permission avise
sed -i "s|<li>You have write permission (777) to <b>\`app/tmp\`</b> folders</li>|<li>\'You have write permission (777) to <b>\`app/tmp\`</b> folders\' \(<em>This is actually hardcoded, <b>please ignore<b></em>\)</li>|" /var/www/html/orangescrum/app/View/Users/login.ctp
# Fix issue #126
sed -i 's|include("install.php");|//include("install.php");|' $APPROOT/app/Config/core.php

cat << HTTPS_CREATE > "$HTTPS_CONF"
<VirtualHost *:80>
	ServerAdmin webmaster@$OSDOMAIN
	DocumentRoot $APPROOT/
	ServerName $OSDOMAIN
	ServerAlias www.$OSDOMAIN

	<Directory $APPROOT/>
		Options FollowSymLinks
		AllowOverride All
		Order allow,deny
		allow from all
	</Directory>

	ErrorLog /var/log/apache2/$OSDOMAIN-error.log
	CustomLog /var/log/apache2/$OSDOMAIN-access.log common
</VirtualHost>
HTTPS_CREATE

a2ensite $CONF_FILE
service apache2 restart
apt -y dist-upgrade
apt -y autoremove
apt autoclean

echo "
OrangeScrum Community Edition Installation Completed Successfully.
Check your server at:
http://$ADDRESS or
http://$OSDOMAIN (if you have configured DNS)"

echo "Rebooting in..."
secs=$((15))
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done
reboot
