#!/bin/bash
# Starts the regular eScriptorium services inside a Galaxy job and imports the
# inputs staged by the tool wrapper under inputs/{documents,annotations,segmentation,recognition}.
# Each inputs/documents/NNNN folder becomes one document: `name` holds its title, `names` the page names without extension,
# and the numbered files are its pages.
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

# Create the session user, its project, one document per inputs/documents folder, and an API token.
# Any superuser is deactivated so no admin account is reachable in this session.
# The transaction makes all documents appear at once for the login redirect.
# The shell prints "RESULT <token>" and one "RESULT <document pk> <folder>" line per document.
[[ -n $(echo inputs/documents/*/) ]] || { echo "Select at least one image, PDF or collection." >&2; exit 1; }
# The folders and titles are passed as "folder<TAB>title" lines because the job directory may not be readable for the escriptorium user.
titles=$(for folder in inputs/documents/*/; do printf '%s\t%s\n' "${folder%/}" "$(<"${folder}name")"; done)
result=$(cd "$app" && runuser -u escriptorium -- env TITLES="$titles" python manage.py shell -c "
import os
from django.db import transaction
from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token
from core.models import Document, Project
User = get_user_model()
User.objects.filter(is_superuser=True).update(is_active=False, is_staff=False, is_superuser=False)
with transaction.atomic():
    user = User.objects.create_user('galaxy_' + os.environ['GALAXY_USER_ID'], os.environ['GALAXY_USER_EMAIL'])
    project = Project.objects.create(name='Galaxy', owner=user)
    print('RESULT', Token.objects.create(user=user).key)
    for line in os.environ['TITLES'].split('\\n'):
        folder, title = line.split('\\t', 1)
        document = Document.objects.create(name=title, owner=user, project=project)
        print('RESULT', document.pk, folder)
" | sed -n 's/^RESULT //p')
token=$(head -n 1 <<< "$result")
documents=$(tail -n +2 <<< "$result")

until curl -fso /dev/null http://127.0.0.1:8000/; do sleep 2; done
# A failed upload is logged to the job stderr and the session keeps running.
api() { curl -sS --fail-with-body -H "Authorization: Token $token" "$@" || echo "Import failed: $*" >&2; }
base=http://127.0.0.1:8000/api

# PDF and XML imports run as Celery tasks in submission order, after the image uploads.
while read -r document folder; do
    for file in "$folder"/*.*; do
        case $file in
            *.pdf) api -F mode=pdf -F "upload_file=@$file" "$base/documents/$document/import/" ;;
            *) api -F "image=@$file" "$base/documents/$document/parts/" ;;
        esac
    done
done <<< "$documents"
# Zip archives go to every document. An XML file goes to the documents holding the image it names, or to every document if it names none.
for file in inputs/annotations/*/*; do
    image=
    [[ $file == *.zip ]] || image=$(grep -oPm1 '(imageFilename="|<fileName>)\K[^"<]+' "$file" || true)
    image=$(basename "${image:-.}"); image=${image%.*}
    while read -r document folder; do
        [[ $image == . ]] || grep -qxF -- "$image" "$folder/names" || continue
        api -F mode=xml -F "upload_file=@$file" "$base/documents/$document/import/"
    done <<< "$documents"
done
for job in segmentation recognition; do
    label=$([[ $job == segmentation ]] && echo Segment || echo Recognize)
    for file in inputs/$job/*/*; do
        api -F "name=$(basename "$file")" -F "job=$label" -F "file=@$file" "$base/models/"
    done
done

wait "$supervisord_pid"
