# Docker deployment for Revive Adserver

This repository can run in a standard Apache/PHP container. The image below uses PHP 8.1, installs the extensions required by the project, and includes the Redis extension so the delivery cache can be switched to a cluster-safe backend.

## Build the image

Provide a direct download URL for the Redis Caching plugin ZIP, save it to a local file, then build:

```bash
export APREDIS_PLUGIN_URL="https://codeload.github.com/adserverplugins/apDeliveryCacheRedis/zip/refs/tags/v1.4.0"
printf '%s' "${APREDIS_PLUGIN_URL}" > /tmp/apredis_plugin_url.txt

docker build \
  --secret id=apredis_plugin_url,src=/tmp/apredis_plugin_url.txt \
  -t revive-adserver:latest .
```

Optional integrity check:

```bash
docker build \
  --secret id=apredis_plugin_url,src=/tmp/apredis_plugin_url.txt \
  --build-arg APREDIS_PLUGIN_SHA256="<sha256-of-zip>" \
  -t revive-adserver:latest .
```

## Run the supporting services

Revive Adserver needs a database, and for clustered delivery cache it should also use Redis instead of the default file cache.

```bash
docker network create revive-net

docker run -d \
  --name revive-db \
  --network revive-net \
  -e MYSQL_DATABASE=revive \
  -e MYSQL_USER=revive \
  -e MYSQL_PASSWORD=revive-secret \
  -e MYSQL_ROOT_PASSWORD=root-secret \
  -v revive-db:/var/lib/mysql \
  mariadb:11

docker run -d \
  --name revive-redis \
  --network revive-net \
  redis:7-alpine
```

## Start Revive Adserver

Mount `var/` as persistent storage so the generated configuration survives container restarts.

```bash
docker run -d \
  --name revive-web \
  --network revive-net \
  -p 8080:80 \
  -v revive-var:/var/www/html/var \
  revive-adserver:latest
```

Open `http://localhost:8080/www/admin/install.php` in your browser and complete the normal Revive Adserver installer. The app will redirect to the installer automatically until installation is complete.

## Configure Redis via docker run --env

The container entrypoint can write Redis cache settings into existing Revive config files in `var/*.conf.php`.

Set these environment variables on the web container:

- `REVIVE_REDIS_HOST` default `revive-redis`.
- `REVIVE_REDIS_PORT` default `6379`.
- `REVIVE_REDIS_TIMEOUT` default `1.0`.
- `REVIVE_REDIS_DATABASE` default `0`.
- `REVIVE_REDIS_PERSISTENT` default `0`.
- `REVIVE_REDIS_IGBINARY` default `0`.
- `REVIVE_REDIS_SOCKET` default empty.

Example:

```bash
docker run -d \
  --name revive-web \
  --network revive-net \
  -p 8080:80 \
  -v revive-var:/var/www/html/var \
  --env REVIVE_REDIS_HOST=revive-redis \
  --env REVIVE_REDIS_PORT=6379 \
  --env REVIVE_REDIS_TIMEOUT=1.0 \
  --env REVIVE_REDIS_DATABASE=0 \
  --env REVIVE_REDIS_PERSISTENT=0 \
  --env REVIVE_REDIS_IGBINARY=0 \
  revive-adserver:latest
```

The image build installs the Redis Caching plugin into:

`/var/www/html/plugins/deliveryCacheStore/apRedis/apRedis.class.php`

The container then enforces `deliveryCacheStore:apRedis:apRedis` for runtime config files.

## Verify Redis caching is active

1. Verify the running web container config is set to apRedis:

```bash
docker exec revive-web sh -lc '
  conf_file="$(ls /var/www/html/var/*.conf.php | head -n1)" &&
  echo "Using config: ${conf_file}" &&
  grep -E "cacheStorePlugin|^\[apRedis\]|host[[:space:]]*=" "${conf_file}"
'
```

Expected output includes:

- `cacheStorePlugin = deliveryCacheStore:apRedis:apRedis`
- `[apRedis]`
- `host = revive-redis` (or your configured Redis host)

2. Verify Revive is issuing Redis cache commands:

```bash
docker exec revive-redis redis-cli CONFIG RESETSTAT

# Trigger delivery traffic (use a real delivery URL from your setup).
for i in $(seq 1 20); do
  curl -fsS "http://localhost:8080/www/delivery/avw.php?zoneid=1&cb=${RANDOM}" >/dev/null || true
done

docker exec revive-redis redis-cli INFO commandstats | \
  grep -E 'cmdstat_(get|set|setex|del|expire)'
```

Expected output includes one or more non-zero `cmdstat_*` counters (for example
`cmdstat_get`, `cmdstat_setex`, or `cmdstat_expire`) after traffic is sent.

That confirms Revive is actively using Redis for delivery cache operations, not
just that Redis is reachable.

If no `cmdstat_*` counters increase, verify the delivery URL is valid for your
installation and re-check that `cacheStorePlugin = deliveryCacheStore:apRedis:apRedis`
is present in the active `var/*.conf.php` file.

## Cluster mode

For multiple web servers behind a load balancer, use the same image on every node and keep the database shared. Do not rely on the default file delivery cache, because it is node-local.

After installation, the entrypoint will set the cache store plugin and Redis connection in your generated configuration file (`var/your-hostname.conf.php`):

```ini
[delivery]
cacheStorePlugin = deliveryCacheStore:apRedis:apRedis

[apRedis]
host = revive-redis
port = 6379
timeout = 1.0
database = 0
persistent = 0
igbinary = 0
socket =
```

If you are using a Unix socket instead of TCP, set `socket` and leave `host`/`port` unused by your environment.

```ini
socket = /var/run/redis/redis.sock
```

The delivery cache expiry is still controlled by `[delivery] cacheExpire`.

## Suggested production layout

- One image build shared by all web nodes.
- One shared database.
- One shared Redis service for delivery cache.
- A persistent shared `var/` volume, or an equivalent mechanism to keep the generated configuration identical across nodes.