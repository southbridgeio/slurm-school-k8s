#!/usr/bin/env bash

DIR="etc/nginx/"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


log() {
    case $1 in
        error)
            LOG_LEVEL="error"
            COLOR=$RED
            ;;
        notice)
            LOG_LEVEL="notice"
            COLOR=$GREEN
            ;;
    esac

    timestamp="$(date +"%Y/%m/%d %H:%M:%S")"
    echo -e "$timestamp [$LOG_LEVEL] $0: ${COLOR}$2${NC}"
}

getmd5() {
    tar --strip-components=2 -C / -cf - $DIR | md5sum | awk '{print $1}'
}


if [ ! -d $DIR ]; then
    log error "/$DIR not found"
    exit 1
fi

if ! [ -x "$(command -v nginx)" ]; then
  log error "Nginx is not installed"
  exit 1
fi

log notice "starting Nginx process..."
nginx -g 'daemon off;' &

log notice "watching /$DIR for changes..."
checksum_initial=$(getmd5)

trap "exit 0" SIGINT SIGTERM
while true; do
    ps aux | grep 'master process nginx' | grep -q -v grep
    NGINX_STATUS=$?
    if [ $NGINX_STATUS -ne 0 ]; then
        log error "Nginx exited. Stopping entrypoint script..."
        exit 1
    fi
    checksum_current=$(getmd5)
    if [ "$checksum_initial" != "$checksum_current" ]; then
        checksum_initial=$checksum_current

        nginx -tq
        NGINX_CONF_STATUS=$?
        if [ $NGINX_CONF_STATUS -ne 0 ]; then
            log error "couldn't reload Nginx due to an error in the config file"
            continue
        fi

        nginx -s reload
        log notice "reloaded Nginx config"
    fi
    sleep 5
done
