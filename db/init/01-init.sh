#!/usr/bin/env bash

export PGPASSWORD='secret';
psql -U postgres -d postgres -c "create user xrad_user with encrypted password 'xrad_user';"
psql -U postgres -d postgres -c "create user app_user with encrypted password 'app_user';"
psql -U postgres -d postgres -c "CREATE DATABASE \"appdb\" WITH OWNER \"app_user\" ENCODING 'UTF8' LC_COLLATE = 'ru_RU.UTF-8' LC_CTYPE = 'ru_RU.UTF-8' TEMPLATE template0;"
psql -U postgres -d postgres -c "CREATE DATABASE \"xraddb\" WITH OWNER \"xrad_user\" ENCODING 'UTF8' LC_COLLATE = 'ru_RU.UTF-8' LC_CTYPE = 'ru_RU.UTF-8' TEMPLATE template0;"
psql -U postgres -d postgres -c "ALTER USER xrad_user WITH SUPERUSER;"
psql -U postgres -d postgres -c "ALTER USER app_user WITH SUPERUSER;"

export PGPASSWORD='app_user';
psql -U app_user -d appdb -c "CREATE EXTENSION http;"
