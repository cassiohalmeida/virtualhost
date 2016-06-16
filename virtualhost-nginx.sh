#!/bin/bash
### Set Language
TEXTDOMAIN=virtualhost

### Set default parameters
action=$1
domain=$2
rootDir=$3
email=$4
owner=$(who am i | awk '{print $1}')
sitesEnable='/etc/nginx/sites-enabled/'
sitesAvailable='/etc/nginx/sites-available/'
userDir='/var/www/'

if [ "$(whoami)" != 'root' ]; then
	echo $"You have no permission to run $0 as non-root user. Use sudo"
		exit 1;
fi

if [ "$action" != 'create' ] && [ "$action" != 'delete' ]
	then
		echo $"You need to prompt for action (create or delete) -- Lower-case only"
		exit 1;
fi

while [ "$domain" == "" ]
do
	echo -e $"Please provide domain. e.g.dev,staging"
	read domain
done

while [ "$email" == "" ]
do
	echo -e $"Please provide a valid e-mail."
	read email
done

if [ "$rootDir" == "" ]; then
	rootDir=${domain//./}
fi

### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

rootDir=$userDir$rootDir

if [ "$action" == 'create' ]
	then
		### check if domain already exists
		if [ -e $sitesAvailable$domain ]; then
			echo -e $"This domain already exists.\nPlease Try Another one"
			exit;
		fi

		### check if directory exists or not
		if ! [ -d $userDir$rootDir ]; then
			### create the directory
			mkdir -p $userDir$rootDir
			### give permission to root dir
			chmod 755 $userDir$rootDir
			### write test file in the new domain dir
			if ! echo "<?php echo phpinfo(); ?>" > $userDir$rootDir/phpinfo.php
				then
					echo $"ERROR: Not able to write in file $userDir/$rootDir/phpinfo.php. Please check permissions."
					exit;
			else
					echo $"Added content to $userDir$rootDir/phpinfo.php."
			fi
		fi

		### create virtual host rules file
		if ! echo "
			server {
				listen 80;
        		server_name $domain www.$domain;
        		return 301 https://$host$request_uri;
			}
			server {
				listen 443 ssl;
				root $userDir$rootDir;
				index index.php index.html index.htm;
				server_name $domain www.$domain;

				ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
				ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
				ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
				ssl_prefer_server_ciphers on;
				ssl_ciphers 'EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5';
				ssl_dhparam /etc/nginx/ssl/dhparams.pem;
				ssl_session_timeout 1d;
				ssl_session_cache shared:SSL:50m;
				ssl_stapling on;
				ssl_stapling_verify on;
				add_header Strict-Transport-Security max-age=15768000;

				# serve static files directly
				location ~* \.(jpg|jpeg|gif|css|png|js|ico|html)$ {
					access_log off;
					expires max;
				}

				# removes trailing slashes (prevents SEO duplicate content issues)
				if (!-d \$request_filename) {
					rewrite ^/(.+)/\$ /\$1 permanent;
				}

				# unless the request is for a valid file (image, js, css, etc.), send to bootstrap
				if (!-e \$request_filename) {
					rewrite ^/(.*)\$ /index.php?/\$1 last;
					break;
				}

				# removes trailing 'index' from all controllers
				if (\$request_uri ~* index/?\$) {
					rewrite ^/(.*)/index/?\$ /\$1 permanent;
				}

				# catch all
				error_page 404 /index.php;

				location ~ \.php$ {
					fastcgi_split_path_info ^(.+\.php)(/.+)\$;
					fastcgi_pass unix:/run/php/php7.0-fpm.sock;
					fastcgi_index index.php;
					include fastcgi_params;
					fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
				}

				location ~ /\.ht {
					deny all;
				}

				location ~ /.well-known {
                	allow all;
        		}

		}" > $sitesAvailable$domain
		then
			echo -e $"There is an ERROR create $domain file"
			exit;
		else
			echo -e $"\nNew Virtual Host Created\n"
		fi

		### Add domain in /etc/hosts
		if ! echo "127.0.0.1	$domain" >> /etc/hosts
			then
				echo $"ERROR: Not able write in /etc/hosts"
				exit;
		else
				echo -e $"Host added to /etc/hosts file \n"
		fi

		if [ "$owner" == "" ]; then
			chown -R $(whoami):www-data $userDir$rootDir
		else
			chown -R $owner:www-data $userDir$rootDir
		fi

		### enable website
		ln -s $sitesAvailable$domain $sitesEnable$domain

		### stop Nginx
		service nginx stop

		##Check if domain has a lets encrypt certificate.
		if [ ! -d /etc/letsencrypt/live/$domain ]; then
			echo -e $"Installing letsencrypt for domain."
			export LC_ALL="en_US.UTF-8"
			export LC_CTYPE="en_US.UTF-8"
			cd /opt/letsencrypt
			./letsencrypt-auto certonly --standalone --email $email -d $domain -d www.$domain

			if [ ! -d /etc/nginx/ssl ]; then
			  	mkdir -p /etc/nginx/ssl
			  	cd /etc/nginx/ssl
				if [ ! -f /etc/nginx/ssl/dhparams.pem ]; then
					openssl dhparam -out dhparams.pem 2048		
				fi
			fi
		fi
		/etc/init.d/nginx start
		nginx -t

		### show the finished message
		echo -e $"Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $userDir$rootDir"
		exit;
	else
		### check whether domain already exists
		if ! [ -e $sitesAvailable$domain ]; then
			echo -e $"This domain dont exists.\nPlease Try Another one"
			exit;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts

			### disable website
			rm $sitesEnable$domain

			### restart Nginx
			service nginx restart

			### Delete virtual host rules files
			rm $sitesAvailable$domain
		fi

		### check if directory exists or not
		if [ -d $userDir$rootDir ]; then
			echo -e $"Delete host root directory ? (s/n)"
			read deldir

			if [ "$deldir" == 's' -o "$deldir" == 'S' ]; then
				### Delete the directory
				rm -rf $userDir$rootDir
				echo -e $"Directory deleted"
			else
				echo -e $"Host directory conserved"
			fi
		else
			echo -e $"Host directory not found. Ignored"
		fi

		### show the finished message
		echo -e $"Complete!\nYou just removed Virtual Host $domain"
		exit 0;
fi