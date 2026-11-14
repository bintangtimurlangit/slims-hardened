# slims-hardened: SLiMS 9 on a current PHP 8.3, locked down. See HARDENING.md.

# --- Composer dependencies (build tools stay out of the final image) ---
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
# SLiMS ships a patched ifsnop/mysqldump-php in lib/ that accepts its PDO connection;
# the stock Composer copy would load first and break Backup ("Empty DSN string").
# setasign/fpdi is bumped past CVE-2026-45802. The audit fails the build on any known advisory.
RUN composer remove ifsnop/mysqldump-php --no-install --no-scripts --ignore-platform-reqs --no-interaction \
    && composer update setasign/fpdi --no-install --no-scripts --ignore-platform-reqs --no-interaction \
    && composer audit --locked --no-interaction
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist \
        --ignore-platform-reqs --no-scripts --no-autoloader
COPY src ./src
RUN composer dump-autoload --no-dev --optimize

# --- Runtime ---
FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libicu-dev libxml2-dev libzip-dev libpng-dev libonig-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" intl gettext mbstring zip mysqli pdo_mysql gd \
    && rm -rf /var/lib/apt/lists/*

# PEAR File_MARC: needed by Bibliography > MARC Import (upstream image lacks it).
RUN pear install File_MARC && rm -rf /tmp/pear ~/.pearrc

# PHP: production defaults plus our lockdown.
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/php-hardening.ini "$PHP_INI_DIR/conf.d/zz-hardening.ini"

# Apache: lockdown config, real client IP, and listen on 8080 so it runs without root.
COPY docker/apache-hardening.conf /etc/apache2/conf-available/slims-hardening.conf
RUN a2enmod rewrite headers remoteip \
    && a2enconf slims-hardening \
    && sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
    && sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf

WORKDIR /var/www/html

# Code is owned by root and read-only to the web server; only data folders are writable.
COPY --from=vendor /app/vendor ./vendor
COPY . .
RUN rm -rf install docker entrypoint.sh \
    && chown root:root /var/www/html && chmod 755 /var/www/html \
    && chown -R www-data:www-data files images repository config

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

USER www-data
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
