#!/bin/sh

# Write environment variables to env.php
cat <<EOF >/var/www/html/config/env.php
<?php
\$env = "${ENV}";
\$conditional_environment = "${ENV}";
\$based_on_ip = false;
\$range_ip = [''];
if (\$based_on_ip) {
    if (array_key_exists('HTTP_X_FORWARDED_FOR', \$_SERVER) && in_array(\$_SERVER['HTTP_X_FORWARDED_FOR'], \$range_ip)) {
        \$env = \$conditional_environment;
    } else if (in_array(\$_SERVER['REMOTE_ADDR'], \$range_ip)) {
        \$env = \$conditional_environment;
    }   
}
EOF

echo "PHP configuration file created: /var/www/html/config/env.php"

# Behind a TLS-terminating proxy, SLiMS must be told to build https:// links.
FORCE_HTTPS_PHP=false
[ "${FORCE_HTTPS:-0}" = "1" ] && FORCE_HTTPS_PHP=true
cat <<EOF >/var/www/html/config/url.php
<?php
return [
    'base' => '',
    'force_https' => ${FORCE_HTTPS_PHP}
];
EOF

# Write environment variables to database.php
cat <<EOF >/var/www/html/config/database.php
<?php
return [
    'default_profile' => 'SLiMS',
    'proxy' => false,
    'nodes' => [
        'SLiMS' => [
            'host' => '${DB_HOST}',
            'database' => '${DB_NAME}',
            'port' => '${DB_PORT}',
            'username' => '${DB_USER}',
            'password' => '${DB_PASS}',
            'options' => [
                'storage_engine' => 'MyISAM'
            ]
        ]
    ]
];
EOF

chmod 600 /var/www/html/config/database.php
# Not printed: it contains the database password.
echo "PHP configuration file created: /var/www/html/config/database.php"

# Wait for database to be ready
echo "Waiting for database to be ready..."
until php -r "
\$conn = new mysqli(getenv('DB_HOST'), getenv('DB_USER'), getenv('DB_PASS'), getenv('DB_NAME'), (int)getenv('DB_PORT'));
exit(\$conn->connect_error ? 1 : 0);
" 2>/dev/null; do
    echo "  Database not ready, retrying in 2s..."
    sleep 2
done
echo "Database is ready."

# Randomize admin password on first startup only
INIT_FLAG="/var/www/html/files/.admin_initialized"
if [ ! -f "$INIT_FLAG" ]; then
    # Use ADMIN_INITIAL_PASSWORD if given, otherwise generate one and print it once.
    if [ -n "${ADMIN_INITIAL_PASSWORD:-}" ]; then
        ADMIN_PASS="$ADMIN_INITIAL_PASSWORD"; SHOW_PASS=0
    else
        ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16); SHOW_PASS=1
    fi
    export ADMIN_PASS
    ADMIN_HASH=$(php -r "echo password_hash(getenv('ADMIN_PASS'), PASSWORD_BCRYPT);")
    export ADMIN_HASH

    php -r "
\$conn = new mysqli(getenv('DB_HOST'), getenv('DB_USER'), getenv('DB_PASS'), getenv('DB_NAME'), (int)getenv('DB_PORT'));
if (\$conn->connect_error) {
    echo 'DB connection failed: ' . \$conn->connect_error . PHP_EOL;
    exit(1);
}
\$stmt = \$conn->prepare('UPDATE user SET passwd=? WHERE username=?');
\$hash = getenv('ADMIN_HASH');
\$user = 'admin';
\$stmt->bind_param('ss', \$hash, \$user);
\$stmt->execute();
if (\$stmt->affected_rows > 0) {
    echo 'Admin password updated successfully.' . PHP_EOL;
} else {
    echo 'Warning: admin user not found or password unchanged.' . PHP_EOL;
}
\$stmt->close();
\$conn->close();
"

    touch "$INIT_FLAG"
    unset ADMIN_HASH

    echo ""
    echo "========================================================"
    echo "  SLIMS FIRST-TIME SETUP - ADMIN CREDENTIALS"
    echo "  Username : admin"
    if [ "$SHOW_PASS" = 1 ]; then echo "  Password : ${ADMIN_PASS}"; else echo "  Password : (set from ADMIN_INITIAL_PASSWORD)"; fi
    echo "  Please change your password immediately after login!"
    echo "========================================================"
    echo ""

    unset ADMIN_PASS
else
    echo "Admin password already initialized, skipping."
fi

# Start the PHP application
exec "$@"
