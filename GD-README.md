# Docker deployment for Revive Adserver

This repository can run in a standard Apache/PHP container. The image below uses PHP 8.1, installs the extensions required by the project, and includes the Memcached extension so the delivery cache can be switched to a cluster-safe backend.

## Build the image

```bash
docker build -t revive-adserver:latest .
```

## Run the supporting services

Revive Adserver needs a database, and for clustered delivery cache it should also use Memcached instead of the default file cache.

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
  --name revive-memcached \
  --network revive-net \
  memcached:1.6-alpine
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

## Cluster mode

For multiple web servers behind a load balancer, use the same image on every node and keep the database shared. Do not rely on the default file delivery cache, because it is node-local.

After installation, switch the delivery cache to the bundled Memcached plugin and point it at the shared Memcached service:

```ini
[delivery]
cacheStorePlugin = deliveryCacheStore:oxMemcached:oxMemcached

[oxMemcached]
memcachedServers = revive-memcached:11211
memcachedExpireTime = 3600
```

If you use more than one Memcached server, separate them with commas:

```ini
memcachedServers = memcached-a:11211,memcached-b:11211
```

The `memcachedExpireTime` value must be greater than the delivery cache expiry value.

## Suggested production layout

- One image build shared by all web nodes.
- One shared database.
- One shared Memcached cluster for delivery cache.
- A persistent shared `var/` volume, or an equivalent mechanism to keep the generated configuration identical across nodes.