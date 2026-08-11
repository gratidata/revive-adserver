# Docker deployment for Revive Adserver

This repository can run in a standard Apache/PHP container. The image below uses PHP 8.1, installs the extensions required by the project, and includes the Redis extension so the delivery cache can be switched to a cluster-safe backend.

## Build the image

```bash
docker build -t revive-adserver:latest .
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

The container enforces `deliveryCacheStore:apRedis:apRedis` for runtime config files, so the Redis Caching plugin must be installed in Revive.

## Cluster mode

For multiple web servers behind a load balancer, use the same image on every node and keep the database shared. Do not rely on the default file delivery cache, because it is node-local.

After installation, install the Redis Caching plugin from https://www.adserverplugins.com/redis-caching-plugin/ and switch the delivery cache to Redis.

Then configure the cache store plugin and Redis connection in your generated configuration file (`var/your-hostname.conf.php`):

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