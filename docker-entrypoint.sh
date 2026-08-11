#!/bin/sh
set -e

set_ini_value() {
  file="$1"
  section="$2"
  key="$3"
  value="$4"

  tmp_file="$(mktemp)"

  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
      in_section = 0
      section_found = 0
      key_set = 0
    }

    {
      if ($0 ~ /^\[[^]]+\][[:space:]]*$/) {
        if (in_section && !key_set) {
          print key " = " value
          key_set = 1
        }

        if ($0 == "[" section "]") {
          in_section = 1
          section_found = 1
        } else {
          in_section = 0
        }

        print $0
        next
      }

      if (in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
        if (!key_set) {
          print key " = " value
          key_set = 1
        }
        next
      }

      print $0
    }

    END {
      if (!section_found) {
        print ""
        print "[" section "]"
        print key " = " value
      } else if (in_section && !key_set) {
        print key " = " value
      }
    }
  ' "$file" > "$tmp_file"

  if [ -f "$file" ]; then
    chown --reference="$file" "$tmp_file" 2>/dev/null || true
    chmod --reference="$file" "$tmp_file" 2>/dev/null || true
  fi

  mv "$tmp_file" "$file"
}

apply_redis_env_config() {
  redis_host="${REVIVE_REDIS_HOST:-revive-redis}"
  redis_port="${REVIVE_REDIS_PORT:-6379}"
  redis_timeout="${REVIVE_REDIS_TIMEOUT:-1.0}"
  redis_database="${REVIVE_REDIS_DATABASE:-0}"
  redis_persistent="${REVIVE_REDIS_PERSISTENT:-0}"
  redis_igbinary="${REVIVE_REDIS_IGBINARY:-0}"
  redis_socket="${REVIVE_REDIS_SOCKET:-}"

  found_conf=0
  for conf_file in /var/www/html/var/*.conf.php; do
    if [ ! -f "$conf_file" ]; then
      continue
    fi

    found_conf=1

    set_ini_value "$conf_file" "delivery" "cacheStorePlugin" "deliveryCacheStore:apRedis:apRedis"

    set_ini_value "$conf_file" "apRedis" "host" "$redis_host"
    set_ini_value "$conf_file" "apRedis" "port" "$redis_port"
    set_ini_value "$conf_file" "apRedis" "timeout" "$redis_timeout"
    set_ini_value "$conf_file" "apRedis" "database" "$redis_database"
    set_ini_value "$conf_file" "apRedis" "persistent" "$redis_persistent"
    set_ini_value "$conf_file" "apRedis" "igbinary" "$redis_igbinary"
    set_ini_value "$conf_file" "apRedis" "socket" "$redis_socket"

    echo "Applied Redis cache settings to ${conf_file}"
  done

  if [ "$found_conf" = "0" ]; then
    echo "No Revive config found in /var/www/html/var/*.conf.php yet; Redis settings will be applied on next container start after install"
  fi
}

mkdir -p \
  /var/www/html/var \
  /var/www/html/var/cache \
  /var/www/html/var/plugins \
  /var/www/html/var/templates_compiled \
  /var/www/html/plugins \
  /var/www/html/www/admin/plugins \
  /var/www/html/www/images

apply_redis_env_config

chown -R www-data:www-data \
  /var/www/html/var \
  /var/www/html/plugins \
  /var/www/html/www/admin/plugins \
  /var/www/html/www/images

exec "$@"
