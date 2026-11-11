FROM php:8.2-apache
# Amélioration possible (Partie 5) : épingler l'image par digest, ex. php:8.2-apache@sha256:...

ARG DEBIAN_FRONTEND=noninteractive

ARG SQLITE_VERSION=3430200
ARG SQLITE_YEAR=2023

# Xdebug n'a rien à faire en production : installé seulement si INSTALL_XDEBUG=true
ARG INSTALL_XDEBUG=false
ARG XDEBUG_VERSION="3.3.0"

ARG BUILD_DATE
ARG TAG
ARG GIT_COMMIT
ARG GIT_URL
ARG PROJECT_USERNAME="SI5"

ENV VERSION="${TAG}"

# Metadata (OCI)
LABEL maintainer="${PROJECT_USERNAME}" \
      org.opencontainers.image.authors="${PROJECT_USERNAME}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.url="${GIT_URL}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="${PROJECT_USERNAME}" \
      org.opencontainers.image.licenses="proprietary" \
      org.opencontainers.image.title="PHP Devops TP" \
      org.opencontainers.image.description="Example of a PHP application automatically encapsulated inside a docker container by the CI pipeline" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="${GIT_URL}"

ENV DATABASE_DRIVER=sqlite
ENV DATABASE_DATABASE=/var/www/html/database/db.sqlite

# System dependencies (--no-install-recommends = image plus petite, moins de surface d'attaque)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    unzip \
    wget \
    curl \
    ca-certificates \
    bash

# sqlite3 CLI
RUN mkdir /opt/sqlite3 \
    && cd /opt/sqlite3 \
    && wget -q https://www.sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz \
    && tar xfz sqlite-autoconf-${SQLITE_VERSION}.tar.gz \
    && cd sqlite-autoconf-${SQLITE_VERSION} \
    && CFLAGS="-O2 -DSQLITE_ENABLE_COLUMN_METADATA=1" ./configure \
    && make -j$(nproc) \
    && make install \
    && ln -s /usr/local/bin/sqlite3 /usr/bin/sqlite3 \
    && rm -Rf /opt/sqlite3 \
    && sqlite3 --version

# Xdebug (optionnel, dev uniquement)
RUN if [ "$INSTALL_XDEBUG" = "true" ]; then \
      pecl install xdebug-${XDEBUG_VERSION} && docker-php-ext-enable xdebug; \
    fi

# PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j$(nproc) gd pdo pdo_mysql zip pdo_sqlite

# Infisical CLI : le dépôt Cloudsmith ne sert plus la CLI depuis le 16/09/2026,
# nouveau dépôt officiel : artifacts-cli.infisical.com
RUN curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash \
    && apt-get update \
    && apt-get install -y --no-install-recommends infisical \
    && infisical --version

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Apache : mod_rewrite + DocumentRoot sur public/ + pas de bannière de version
RUN a2enmod rewrite \
    && sed -i 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/000-default.conf \
    && printf "ServerTokens Prod\nServerSignature Off\n" > /etc/apache2/conf-available/zz-security.conf \
    && a2enconf zz-security \
    && echo "expose_php = Off" > /usr/local/etc/php/conf.d/zz-security.ini

WORKDIR /var/www/html

# Dépendances d'abord (cache des couches Docker), sans les dépendances de dev
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts --no-autoloader

# Code de l'application
COPY . /var/www/html
RUN composer dump-autoload --no-dev --optimize \
    && rm -Rf /var/www/html/docker /var/www/html/Docker /var/www/html/scripts \
    && rm -f /var/www/html/public/info.php

# Le code appartient à root (non modifiable par Apache), seul database/ est inscriptible
RUN mkdir -p /var/www/html/database \
    && chown -R root:root /var/www/html \
    && chown -R www-data:www-data /var/www/html/database

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost/ || exit 1

EXPOSE 80
