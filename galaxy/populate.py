"""Add eScriptorium inputs: the session user, default project, one document per Document block, models.
Usage: populate.py <inputs.json>
"""
import json
import os
import sys

import django

django.setup()

from django.contrib.auth import get_user_model  # noqa: E402
from django.core.files import File  # noqa: E402
from django.db import transaction  # noqa: E402

from core.forms import ModelUploadForm  # noqa: E402
from core.models import Document, Project  # noqa: E402


def filename(dataset):
    """Returns the dataset name with the extension of its Galaxy datatype."""
    name = str(dataset["element_identifier"]).replace("/", "_")
    extension = "." + dataset["ext"]
    return name if name.lower().endswith(extension) else name + extension


def create_pages(documents, inputs):
    """Creates the pages of all documents in the selected order, PDF pages at the position of their PDF."""
    # TODO: create the pages
    print("Creating pages is not implemented yet.", file=sys.stderr)


def import_models(user, models):
    """Imports the models; the upload form detects whether a model segments or recognizes."""
    for dataset in filter(None, models or []):
        name = filename(dataset)
        try:
            with open(dataset["source_path"], "rb") as model:
                form = ModelUploadForm(data={"name": name}, files={"file": File(model, name=name)}, user=user)
                form.instance.owner = user
                if form.is_valid():
                    form.save()
                else:
                    print(f"Model import failed: {name}: {form.errors.as_text()}", file=sys.stderr)
        except Exception as error:
            print(f"Model import failed: {name}: {error!r}", file=sys.stderr)


def main(inputs_path):
    with open(inputs_path) as inputs_file:
        inputs = json.load(inputs_file)

    User = get_user_model()
    # No admin account is reachable in this session.
    User.objects.filter(is_superuser=True).update(is_active=False, is_staff=False, is_superuser=False)
    # The transaction makes all documents appear at once for the login redirect.
    with transaction.atomic():
        user = User.objects.create_user(f"galaxy_{os.environ['GALAXY_USER_ID']}", os.environ["GALAXY_USER_EMAIL"])
        project = Project.objects.create(name="Galaxy", owner=user)
        documents = [Document.objects.create(name=(block["title"] or "").strip() or f"Document {index + 1}",
                                             owner=user, project=project)
                     for index, block in enumerate(inputs["documents"])]
    create_pages(documents, inputs["documents"])
    import_models(user, inputs["input_models"])


if __name__ == "__main__":
    main(sys.argv[1])
