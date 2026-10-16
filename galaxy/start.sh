#!/bin/bash
# Starts the eScriptorium services inside a Galaxy job and imports inputs/documents.
# Each document folder holds its title in `name`, plus numbered page and annotation folders preserving filenames.
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
trap 'kill -TERM "$supervisord_pid" 2>/dev/null || true; wait "$supervisord_pid" || true' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The database schema and static assets are prepared in the image.
deadline=$((SECONDS + 120))
wait_for() {
    local service=$1
    shift
    until "$@"; do
        if (( SECONDS >= deadline )); then
            echo "Timed out waiting for $service." >&2
            return 1
        fi
        sleep 1
    done
}
wait_for PostgreSQL runuser -u postgres -- pg_isready -q

# Create the session user, its project, one document per inputs/documents folder, and an API token.
# Any superuser is deactivated so no admin account is reachable in this session.
# The transaction makes all documents appear at once for the login redirect.
# The shell prints "RESULT <token>" and one "RESULT <document pk> <folder>" line per document.
document_folders=(inputs/documents/*/)
(( ${#document_folders[@]} )) || { echo "Select at least one input file or collection." >&2; exit 1; }
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

wait_for HTTP curl --max-time 2 -fso /dev/null http://127.0.0.1:8000/
# A failed upload is logged to the job stderr and the session keeps running.
api() { curl -sS --fail-with-body -H "Authorization: Token $token" "$@" || echo "Import failed: $*" >&2; }
base=http://127.0.0.1:8000/api

# PDF and XML imports run as Celery tasks in submission order, after the image uploads.
while read -r document folder; do
    for file in "$folder"/pages/*/*; do
        case $file in
            */*.pdf/*) api -F mode=pdf -F "upload_file=@$file" "$base/documents/$document/import/" ;;
            *) api -F "image=@$file" "$base/documents/$document/parts/" ;;
        esac
    done
done <<< "$documents"
# Annotations belong to the document selected in their input group.
while read -r document folder; do
    for file in "$folder"/annotations/*/*; do
        api -F mode=xml -F "upload_file=@$file" "$base/documents/$document/import/"
    done
done <<< "$documents"
for file in inputs/models/*/*/*; do
    (cd "$app" && runuser -u escriptorium -- env MODEL_NAME="$(basename "$file")" python manage.py shell -c "
import os, shutil, sys
from tempfile import NamedTemporaryFile
from django.contrib.auth import get_user_model
from django.core.files import File
from core.forms import ModelUploadForm

user = get_user_model().objects.get(username='galaxy_' + os.environ['GALAXY_USER_ID'])
name = os.environ['MODEL_NAME']
with NamedTemporaryFile(suffix=os.path.splitext(name)[1]) as tmp:
    shutil.copyfileobj(sys.stdin.buffer, tmp)
    tmp.seek(0)
    form = ModelUploadForm(data={'name': name}, files={'file': File(tmp, name=name)}, user=user)
    form.instance.owner = user
    form.save()
" ) < "$file" || echo "Model import failed: $file" >&2
done

wait "$supervisord_pid"
