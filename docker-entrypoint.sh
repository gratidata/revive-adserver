#!/bin/sh
set -e

mkdir -p \
  /var/www/html/var \
  /var/www/html/var/cache \
  /var/www/html/var/plugins \
  /var/www/html/var/templates_compiled \
  /var/www/html/plugins \
  /var/www/html/www/admin/plugins \
  /var/www/html/www/images

chown -R www-data:www-data \
  /var/www/html/var \
  /var/www/html/plugins \
  /var/www/html/www/admin/plugins \
  /var/www/html/www/images

exec "$@"
