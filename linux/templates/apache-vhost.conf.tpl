<VirtualHost *:80>
    ServerName {{DOMAIN}}
    ServerAdmin webmaster@localhost
    DocumentRoot {{DOCUMENT_ROOT}}

    <Directory {{DOCUMENT_ROOT}}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/{{PROJECT_SLUG}}-error.log
    CustomLog ${APACHE_LOG_DIR}/{{PROJECT_SLUG}}-access.log combined
</VirtualHost>
