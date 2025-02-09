#!/bin/bash
# Script for Linux-NGINX-PHP only. debian
# @TODO: Need to add SSL support using certbot.
# @TODO: uncomment `# server_tokens off;`line from this file /etc/nginx/nginx.conf

WEBSITE="example.com"

sudo su
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo 'ERROR: Invalid installer checksum'
    rm composer-setup.php
    exit 1
fi
php composer-setup.php
php -r "unlink('composer-setup.php');"
sudo mv composer.phar /usr/local/bin/composer

WEBSITE=$(echo $WEBSITE | sed -e 's/^https\?:\/\///g' -e 's/\/$//')
apt-get update
################
# Webserver
# You can clone from the project repo here, if you want to automate app installation
mkdir -p /var/www/${WEBSITE}
chown -R www-data:www-data /var/www/${WEBSITE}
apt-get install nginx libssl-dev -y
# domain conf
cat <<END >/etc/nginx/sites-available/${WEBSITE}.conf
server {
    listen 80;
    server_name ${WEBSITE}
    server_tokens off;
    client_max_body_size 20m;
    gzip_http_version 1.0;
    index index.html index.php;
    root /var/www/${WEBSITE}/public;
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    location ~ \..*/.*\.php\$ {
        return 403;
    }
    # Allow "Well-Known URIs" as per RFC 5785
    location ~* ^/.well-known/ {
        allow all;
    }
    # Block access to "hidden" files and directories whose names begin with a
    # period. This includes directories used by version control systems such
    # as Subversion or Git to store control files.
    location ~ (^|/)\. {
        return 403;
    }
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    # Don't allow direct access to PHP files in the vendor directory.
    location ~ /vendor/.*\.php\$ {
        deny all;
        return 404;
    }
    location ~ /\.ht {
            deny all;
    }
    location ~ '\.php\$' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)\$;
        include fastcgi_params;
        fastcgi_read_timeout 300;
        # Block httpoxy attacks. See https://httpoxy.org/.
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
}
END
ln -s /etc/nginx/sites-available/${WEBSITE}.conf /etc/nginx/sites-enabled/${WEBSITE}.conf
rm -rf /etc/nginx/sites-enabled/default
systemctl restart nginx.service
mkdir -p /var/www/${WEBSITE}/public
echo "<?php phpinfo();" > /var/www/${WEBSITE}/public/index.php
chgrp -R www-data /var/www
chmod -R g+w /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod ug+rw {} \;
################
# PHP
# Install php8
sudo apt install lsb-release ca-certificates apt-transport-https software-properties-common -y
sudo add-apt-repository ppa:ondrej/php
apt install php8.2-{cli,fpm,mysqlnd,pdo,xml,curl,dom,exif,fileinfo,gd,iconv,mbstring,phar,xml,zip} -y
sed -i -e 's/pm.max_children = 5$/pm.max_children = 50/g' /etc/php/8.2/fpm/pool.d/www.conf
sed -i -e 's/pm.max_spare_servers = 3$/pm.max_spare_servers = 30/g' /etc/php/8.2/fpm/pool.d/www.conf
sed -i -e 's/upload_max_filesize = 2M$/upload_max_filesize = 8M/g' /etc/php/8.2/fpm/php.ini
sed -i -e 's/post_max_size = 8M$/post_max_size = 8M/g' /etc/php/8.2/fpm/php.ini
sed -i -e 's/;max_input_vars = 1000$/max_input_vars = 10000/g' /etc/php/8.2/fpm/php.ini
systemctl restart php8.2-fpm.service
