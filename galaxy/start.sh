#!/bin/bash
# Starts the eScriptorium services and imports inputs (documents and models) from json as first argument $1.
# A "media" folder in the job working directory is used for exports and collection for galaxy output.
set -euo pipefail

galaxy_dir=$(dirname "$(readlink -f "$0")")
app=/home/escriptorium/escriptorium/app
export PYTHONPATH=$galaxy_dir:$app DJANGO_SETTINGS_MODULE=galaxy_settings
SECRET_KEY=$(head -c 48 /dev/urandom | base64 -w 0)
# size thread pools to the CPUs Galaxy gives to the container
export GALAXY_SLOTS=${GALAXY_SLOTS:-1}
export SECRET_KEY OMP_NUM_THREADS=$GALAXY_SLOTS

mkdir -p media
chown escriptorium:escriptorium media
rm -rf "$app/media"
ln -s "$PWD/media" "$app/media"

# run supervisord in bg and make sure it stops cleanly by trap'ing the galaxy signals on tool cancellation or script exit
/usr/bin/supervisord -n &
supervisord_pid=$!
trap 'kill -TERM "$supervisord_pid" 2>/dev/null || true; wait "$supervisord_pid" || true' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# copy inputs from galaxy json written as first arg
copies=$(mktemp -d)
python "$galaxy_dir/copy_inputs.py" "$1" "$copies"
chown -R escriptorium "$copies"

# wait for 2 min until the database for eScriptorium is ready
deadline=$((SECONDS + 120))
until runuser -u postgres -- pg_isready -q; do
    if (( SECONDS >= deadline )); then
        echo "Timed out waiting for PostgreSQL." >&2
        exit 1
    fi
    sleep 1
done

runuser -u escriptorium -- env -C "$app" python "$galaxy_dir/populate.py" "$copies/inputs.json"
rm -rf "$copies"

wait "$supervisord_pid"
