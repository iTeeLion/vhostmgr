#!/bin/bash

giturl="https://raw.githubusercontent.com/iTeeLion/vhostmgr/main"

cfgpath_nginx_common="configs/nginx_common.conf"
cfgpath_nginx_vhost="configs/nginx_vhost.conf"
cfgpath_nginx_vhost_ssl="configs/nginx_vhost_ssl.conf"

cfgpath_nginxproxy_common="configs/nginxproxy_common.conf"
cfgpath_nginxproxy_vhost="configs/nginxproxy_vhost.conf"
cfgpath_nginxproxy_vhost_ssl="configs/nginxproxy_vhost_ssl.conf"

cfgpath_apache_common="configs/apache_common.conf"
cfgpath_apache_vhost="configs/apache_vhost.conf"
cfgpath_apache_vhost_ssl="configs/apache_vhost_ssl.conf"
cfgpath_apache_phpfpm="configs/apache_php_fpm.conf"

CMD_RELOAD_APACHE="systemctl reload apache2"
CMD_RELOAD_NGINX="systemctl reload nginx"
CFG_DIR_APACHE="/etc/apache2"
CFG_DIR_NGINX="/etc/nginx"
PORT_PROXY="8080"
PORT_SSL_PROXY="8443"

#
#	REPLACE FUNCTIONS
#

function reloadApache(){
    eval $CMD_RELOAD_APACHE
}

function reloadNginx(){
    eval $CMD_RELOAD_NGINX
}

function replaceValue(){
    sed  -i "s/$2/$3/g" $1
}

function replaceAliasApache(){
    if [ -z $ALIAS ]
    then
	    replaceValue $1 "{{ALIAS}}" ""
    else
	    replaceValue $1 "{{ALIAS}}" "ServerAlias $ALIAS"
    fi
}

function replaceAliasNginx(){
    replaceValue $1 "{{ALIAS}}" "$ALIAS"
}

function replaceValues(){
    replaceValue $1 "{{DOMAIN}}" "$DOMAIN"
    replaceValue $1 "{{PORT}}" "$PORT"
    replaceValue $1 "{{PORT_SSL}}" "$PORT_SSL"
    replaceValue $1 "{{DOMAIN_CERT}}" "$DOMAIN_CERT"
    replaceValue $1 "{{PHP_VERSION}}" "$PHP_VERSION"
    replaceValue $1 "{{PORT_PROXY}}" "$PORT_PROXY"
    replaceValue $1 "{{PORT_SSL_PROXY}}" "$PORT_SSL_PROXY"
}

#
#	SSL FUNCTIONS
#

function findSslDir(){
    DOMAIN_CERT=$(find /etc/letsencrypt/live -name "$1*" | tail -n1 | sed -r 's/\/etc\/letsencrypt\/live\///g')
}

function doSslCert(){
    if [ "$USE_LE" == "y" ]
    then
	    findSslDir $DOMAIN
	    if [ -z "$DOMAIN_CERT" ]
	    then
	        echo "Creating new let's encrypt certificate"
	        if [ -z $ALIAS]
	        then
		        certbot certonly --webroot -n -w "/var/www/$DOMAIN/public" -d $DOMAIN
	        else
		        certbot certonly --webroot -n -w "/var/www/$DOMAIN/public" -d $DOMAIN -d $ALIAS
	        fi
	        findSslDir $DOMAIN
	    else
	        echo "Using existing cert"
	    fi
    fi
}

#
#	DO APACHE CONFIGS
#

function doApacheHttp(){
    wget "$giturl/$cfgpath_apache_common" -O ->> "$CFG_APACHE_COMMON"
    wget "$giturl/$cfgpath_apache_phpfpm" -O ->> $CFG_APACHE_COMMON
    replaceValues $CFG_APACHE_COMMON
    replaceAliasApache $CFG_APACHE_COMMON
    wget "$giturl/$cfgpath_apache_vhost" -O ->> "$CFG_APACHE_VHOST"
    replaceValues $CFG_APACHE_VHOST
    enableApacheVhost
    reloadApache
}

function doApacheHttps(){
    wget "$giturl/$cfgpath_apache_vhost_ssl" -O ->> "$CFG_APACHE_VHOST"
    replaceValues $CFG_APACHE_VHOST
    reloadApache
}

function doApache(){
    doApacheHttp
    if [ "$USE_HTTPS" == "y" ]
    then
	    doSslCert
	    doApacheHttps
    fi
}

#
#	DO NGINX CONFIGS
#

function doNginxHttp(){
    wget "$giturl/$cfgpath_nginx_common" -O ->> "$CFG_NGINX_COMMON"
    replaceValues $CFG_NGINX_COMMON
    replaceAliasNginx $CFG_NGINX_COMMON
    wget "$giturl/$cfgpath_nginx_vhost" -O ->> "$CFG_NGINX_VHOST"
    replaceValues $CFG_NGINX_VHOST
    enableNginxVhost
    reloadNginx
}

function doNginxHttps(){
    wget "$giturl/$cfgpath_nginx_vhost_ssl" -O ->> $CFG_NGINX_VHOST
    replaceValues $CFG_NGINX_VHOST
    reloadNginx
}

function doNginx(){
    doNginxHttp
    if [ "$USE_HTTPS" == "y" ]
    then
	    doSslCert
	    doNginxHttps
    fi
}

#
#	DO NGINX PROXY APACHE CONFIGS
#

function doNginxProxyApacheHttp(){
    wget "$giturl/$cfgpath_nginxproxy_common" -O ->> "$CFG_NGINX_COMMON" 
    replaceValues $CFG_NGINX_COMMON
    replaceAliasNginx $CFG_NGINX_COMMON
    wget "$giturl/$cfgpath_nginxproxy_vhost" -O ->> $CFG_NGINX_VHOST
    replaceValues $CFG_NGINX_VHOST
    enableNginxVhost
    reloadNginx

    PORT="$PORT_PROXY"
    doApacheHttp
}

function doNginxProxyApacheHttps(){
    wget "$giturl/$cfgpath_nginxproxy_vhost_ssl" -O ->> $CFG_NGINX_VHOST
    replaceValues $CFG_NGINX_VHOST
    reloadNginx

    PORT_SSL="$PORT_SSL_PROXY"
    USE_LE="n"
    doApacheHttps
}

function doNginxProxyApache(){
    doNginxProxyApacheHttp
    if [ "$USE_HTTPS" == "y" ]
    then
	    doSslCert
	    doNginxProxyApacheHttps
    fi
}

#
#	DIALOGS
#

function chooseConfig(){
    echo "Chose option:"
    echo "1: Nginx"
    echo "2: Apache"
    echo "3: Nginx proxy + Apache"
    read CONFIG
    case "$CONFIG" in
	1)
	    doNginx
	;;
	2)
	    doApache
	;;
	3)
	    doNginxProxyApache
	;;
	*)
	    chooseConfig
	;;
    esac
}

function askDomain(){
    echo "Enter domain: (Example: mysite.ru)"
    read DOMAIN
    DOMAIN_FILE="$DOMAIN.conf"
    DOMAIN_CERT="$DOMAIN"
    CFG_APACHE_COMMON="$CFG_DIR_APACHE/sites/$DOMAIN_FILE"
    CFG_APACHE_VHOST="$CFG_DIR_APACHE/sites-available/$DOMAIN_FILE"
    CFG_APACHE_VHOST_EN="$CFG_DIR_APACHE/sites-enabled/$DOMAIN_FILE"
    CFG_NGINX_COMMON="$CFG_DIR_NGINX/sites/$DOMAIN_FILE"
    CFG_NGINX_VHOST="$CFG_DIR_NGINX/sites-available/$DOMAIN_FILE"
    CFG_NGINX_VHOST_EN="$CFG_DIR_NGINX/sites-enabled/$DOMAIN_FILE"
    CFG_NGINX_VHOST_TMP="$CFG_DIR_NGINX/sites/$DOMAIN_FILE.tmp"
}

function askUseHttps(){
    echo "Create https vhost?: y/n"
    read USE_HTTPS
    case "$USE_HTTPS" in
	"y")
	    USE_CERT="y"
	;;
	"n")
	    USER_CERT="n"
	;;
	*)
	    askUseHttps
	;;
    esac	
}

function askUseLe(){
    echo "Request or use existed \"Let's encrypt\" cert?: y/n"
    echo "NOTE: If you don't want use \"Let's encrypt\" cert, change path to cert in ssl vhost manually!!!"
    read USE_LE
    case "$USE_LE" in
	"y")
	    USE_LE="y"
	;;
	"n")
	    USER_LE="n"
	;;
	*)
	    askUseLe
	;;
    esac
}

function askAlias(){
    echo "Enter alias: (Example: www.mysite.ru)"
    read ALIAS
}

function askPort(){
    echo "Enter port: (Default: 80)"
    read PORT
    if [ -z "$PORT" ]
    then
	    PORT=80
    fi
}

function askPortSsl(){
    echo "Enter ssl port: (Default: 443)"
    read PORT_SSL
    if [ -z "$PORT_SSL" ]
    then
	    PORT_SSL=443
    fi
}

function askPhpVersion(){
    echo "Enter php version: (Options: 5.6|7.0|7.1|7.2|7.3|7.4|8.0)"
    read PHP_VERSION
    if [ -z "$PORT" ]
    then
	    PHP_VERSION=7.0
    fi
}

function createVhostDirs(){
    mkdir -p /var/www/$DOMAIN/public
    mkdir -p /var/www/$DOMAIN/logs
}

function createVhost(){
    askDomain
    askAlias
    askPort
    askPortSsl
    askPhpVersion
    askUseHttps
    askUseLe
    createVhostDirs
    chooseConfig
    echo "Vhost created!"
}

function removeVhost(){
    askDomain
    rm $CFG_APACHE_COMMON
    rm $CFG_APACHE_VHOST
    rm $CFG_NGINX_COMMON
    rm $CFG_NGINX_VHOST
    disableNginxVhost
    disableApacheVhost
    reloadApache
    reloadNginx
}

function enableNginxVhost(){
    ln -s $CFG_NGINX_VHOST $CFG_NGINX_VHOST_EN
    echo "Nginx vhost $DOMAIN enabled."
}

function disableNginxVhost(){
    rm $CFG_NGINX_VHOST_EN
    echo "Nginx vhost $DOMAIN disabled."
}

function enableApacheVhost(){
    ln -s $CFG_APACHE_VHOST $CFG_APACHE_VHOST_EN
    echo "Apache vhost $DOMAIN enabled."
}

function disableApacheVhost(){
    rm $CFG_APACHE_VHOST_EN
    echo "Apache vhost $DOMAIN disabled."
}

function nginxVhostSwitch(){
    echo "1: Enable"
    echo "2: Disable"
    read NGINX_SWITCH
    case "$NGINX_SWITCH" in
	1)
	    enableNginxVhost
	;;
	2)
	    disableNginxVhost
	;;
	*)
	    nginxVhostSwitch
	;;
    esac
}

function askNginxVhostSwitch(){
    askDomain
    nginxVhostSwitch
}

function apacheVhostSwitch(){
    echo "1: Enable"
    echo "2: Disable"
    read APACHE_SWITCH
    case "$APACHE_SWITCH" in
	1)
	    enableApacheVhost "$DOMAIN.conf"
	;;
	2)
	    disableApacheVhost "$DOMAIN.conf"
	;;
	*)
	    apacheVhostSwitch
	;;
    esac
}

function askApacheVhostSwitch(){
    askDomain
    apacheVhostSwitch
}

function mainMenu(){
    echo "Select action:"
    echo "1: Create vHost"
    echo "2: Remove vHost"
    echo "3: Enable/Disable nginx vhost"
    echo "4: Enable/Disable apache vhost"
    read ACTION
    case "$ACTION" in
	1)
	    createVhost
	;;
	2)
	    removeVhost
	;;
	3)
	    askNginxVhostSwitch
	;;
	4) 
	    askApacheVhostSwitch
	;;
	*)
	    mainMenu
	;;
    esac
}

mainMenu
