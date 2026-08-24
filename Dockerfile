# syntax=docker/dockerfile:1.6
FROM php:8.1-apache

ENV COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        ca-certificates \
        curl \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libssl-dev \
        libxml2-dev \
        libzip-dev \
        unzip \
        zlib1g-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" curl gd intl mbstring mysqli opcache pdo_mysql xml zip \
    && yes '' | pecl install redis \
    && docker-php-ext-enable redis \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/html

COPY . /var/www/html

ARG APREDIS_PLUGIN_SHA256=""

RUN --mount=type=secret,id=apredis_plugin_url \
    set -eux; \
    if [ ! -f /run/secrets/apredis_plugin_url ]; then \
      echo "ERROR: Docker build secret 'apredis_plugin_url' is required to enforce Redis cache support." >&2; \
      exit 1; \
    fi; \
    APREDIS_PLUGIN_URL="$(cat /run/secrets/apredis_plugin_url)"; \
    tmp_zip="$(mktemp /tmp/apredis.XXXXXX.zip)"; \
    tmp_dir="$(mktemp -d /tmp/apredis.XXXXXX)"; \
    curl -fsSL "${APREDIS_PLUGIN_URL}" -o "${tmp_zip}"; \
    if [ -n "${APREDIS_PLUGIN_SHA256}" ]; then \
      echo "${APREDIS_PLUGIN_SHA256}  ${tmp_zip}" | sha256sum -c -; \
    fi; \
    unzip -q "${tmp_zip}" -d "${tmp_dir}"; \
    cache_store_file="$(find "${tmp_dir}" -type f -name apRedis.class.php -print -quit)"; \
    if [ -z "${cache_store_file}" ]; then \
      echo "ERROR: apRedis.class.php not found in downloaded plugin package." >&2; \
      exit 1; \
    fi; \
    redis_lib_file="$(find "${tmp_dir}" -type f -path '*/apRedis/Redis.php' -print -quit)"; \
    if [ -z "${redis_lib_file}" ]; then \
      echo "ERROR: apRedis/Redis.php not found in downloaded plugin package." >&2; \
      exit 1; \
    fi; \
    cache_store_src="$(dirname "${cache_store_file}")"; \
    redis_lib_src="$(dirname "${redis_lib_file}")"; \
    mkdir -p /var/www/html/plugins/deliveryCacheStore/apRedis /var/www/html/plugins/apRedis; \
    cp -R "${cache_store_src}"/. /var/www/html/plugins/deliveryCacheStore/apRedis/; \
    cp -R "${redis_lib_src}"/. /var/www/html/plugins/apRedis/; \
    test -f /var/www/html/plugins/deliveryCacheStore/apRedis/apRedis.class.php; \
    test -f /var/www/html/plugins/apRedis/Redis.php; \
    rm -rf "${tmp_zip}" "${tmp_dir}"

RUN composer install --no-dev --no-interaction --no-progress --prefer-dist --optimize-autoloader \
    && mkdir -p /var/www/html/var /var/www/html/var/cache /var/www/html/var/plugins /var/www/html/var/templates_compiled /var/www/html/plugins /var/www/html/www/admin/plugins /var/www/html/www/images \
    && chown -R www-data:www-data /var/www/html/var /var/www/html/plugins /var/www/html/www/admin/plugins /var/www/html/www/images

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]