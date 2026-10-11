#!/bin/bash
# Starts the regular eScriptorium services inside a Galaxy job and imports the
# inputs staged by the tool wrapper under inputs/{images,annotations,segmentation,recognition}/NNNN/<name>.
# The job working directory holds the media folder, so Galaxy collects exports and models from it.
set -euo pipefail
shopt -s nullglob

tool_dir=$(dirname "$(readlink -f "$0")")
app=/home/escriptorium/escriptorium/app
export PYTHONPATH=$tool_dir DJANGO_SETTINGS_MODULE=galaxy_settings
SECRET_KEY=$(python -c 'import secrets; print(secrets.token_urlsafe(50))')
export SECRET_KEY

mkdir -p media
chown escriptorium:escriptorium media
rm -rf "$app/media"
ln -s "$PWD/media" "$app/media"

/usr/bin/supervisord -n &
supervisord_pid=$!

# django-init.sh creates the database and applies migrations, then exits.
# supervisorctl exits nonzero for stopped programs, so only its output is checked.
until [[ $(supervisorctl status django-init 2>/dev/null) =~ EXITED|FATAL ]]; do sleep 2; done
[[ $(supervisorctl status django-init) =~ EXITED ]]

# Create the session user, its default project and document, and an API token.
# Any superuser is deactivated so no admin account is reachable in this session.
read -r token document < <(cd "$app" && runuser -u escriptorium -- python manage.py shell -c "
import os
from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token
from core.models import Document, Project
User = get_user_model()
User.objects.filter(is_superuser=True).update(is_active=False, is_staff=False, is_superuser=False)
user = User.objects.create_user('galaxy_' + os.environ['GALAXY_USER_ID'], os.environ['GALAXY_USER_EMAIL'])
project = Project.objects.create(name='Galaxy', owner=user)
document = Document.objects.create(name='Galaxy import', owner=user, project=project)
print(Token.objects.create(user=user).key, document.pk)
" | tail -n 1)

until curl -fso /dev/null http://127.0.0.1:8000/; do sleep 2; done
# A failed upload is logged to the job stderr and the session keeps running.
api() { curl -sS --fail-with-body -H "Authorization: Token $token" "$@" || echo "Import failed: $*" >&2; }
base=http://127.0.0.1:8000/api

# PDF and XML imports run as Celery tasks in submission order, after the image uploads.
for file in inputs/images/*/*; do
    case $file in
        *.pdf) api -F mode=pdf -F "upload_file=@$file" "$base/documents/$document/import/" ;;
        *) api -F "image=@$file" "$base/documents/$document/parts/" ;;
    esac
done
for file in inputs/annotations/*/*; do
    api -F mode=xml -F "upload_file=@$file" "$base/documents/$document/import/"
done
for job in segmentation recognition; do
    label=$([[ $job == segmentation ]] && echo Segment || echo Recognize)
    for file in inputs/$job/*/*; do
        api -F "name=$(basename "$file")" -F "job=$label" -F "file=@$file" "$base/models/"
    done
done

wait "$supervisord_pid"
