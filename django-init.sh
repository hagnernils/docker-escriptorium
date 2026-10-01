#!/bin/bash

set -e

export POSTGRES_DB=escriptorium
export POSTGRES_USER=escriptorium
export POSTGRES_PASSWORD=escriptorium

# Wait for PostgreSQL readiness during Supervisor startup.
until su - postgres -c "pg_isready -q"; do
    sleep 1
done

# Create the service role and database on the first run of a persistent volume.
if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='escriptorium'\"" | grep -q 1; then
    su - postgres -c "psql -c \"CREATE USER escriptorium WITH PASSWORD 'escriptorium';\""
fi

if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='escriptorium'\"" | grep -q 1; then
    su - postgres -c "psql -c \"CREATE DATABASE escriptorium OWNER escriptorium;\""
fi

# Prepare application-owned upload and collected-static directories.
install -d -o escriptorium -g escriptorium \
    /home/escriptorium/escriptorium/app/media \
    /home/escriptorium/escriptorium/app/static

# Apply migrations and collect static assets as the application user.
su escriptorium -p -c "cd /home/escriptorium/escriptorium/app/ && python manage.py migrate && python manage.py collectstatic --noinput"
