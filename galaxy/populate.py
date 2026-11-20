"""Add eScriptorium inputs: the session user, default project, one document per Document block, models.
Usage: populate.py <inputs.json>
"""
import json
import os
import re
import subprocess
import sys

import django
import pyvips

django.setup()

from django.conf import settings  # noqa: E402
from django.contrib.auth import get_user_model  # noqa: E402
from django.core.files import File  # noqa: E402
from django.core.files.base import ContentFile  # noqa: E402
from django.db import transaction  # noqa: E402
from easy_thumbnails.files import get_thumbnailer  # noqa: E402

from core.forms import ModelUploadForm  # noqa: E402
from core.models import Document, DocumentPart, Project  # noqa: E402


def filename(dataset):
    """Returns the dataset name with the extension of its Galaxy datatype."""
    name = str(dataset["element_identifier"]).replace("/", "_")
    extension = "." + dataset["ext"]
    return name if name.lower().endswith(extension) else name + extension


def create_page(document, order, path, name, page):
    """Creates one page. PDF pages are rendered like eScriptorium's PDF import
    (300 dpi PNG named "<pdf>_page_<n>.png"), so its PAGE and ALTO exports match."""
    part = DocumentPart(document=document, order=order, original_filename=name, image_file_size=0)
    if page is None:
        pyvips.Image.new_from_file(path)  # rejects files that are not images
        with open(path, "rb") as image:
            data = image.read()
    else:
        data = pyvips.Image.pdfload(path, page=page, dpi=300, access="sequential").write_to_buffer(".png")
        part.original_filename = f"{name}_page_{page + 1}.png"
        part.source = f"pdf//{name}"
        part.workflow_state = DocumentPart.WORKFLOW_STATE_CONVERTED
    part.image.save(part.original_filename, ContentFile(data), save=False)
    part.image_file_size = part.image.size
    part.save()
    thumbnailer = get_thumbnailer(part.image)
    for options in settings.THUMBNAIL_ALIASES[""].values():
        thumbnailer.get_thumbnail(options)
    part.task("convert", user_pk=document.owner_id)


def create_pages(documents, inputs):
    """Creates the pages of all documents in the selected order, PDF pages at the position of their PDF."""
    pages = []
    for document, block in zip(documents, inputs):
        document_pages = []  # (label, path, name, PDF page or None)
        for dataset in filter(None, block["pages"] or []):
            path, name = dataset["source_path"], filename(dataset)
            if dataset["ext"] == "pdf":
                # An unreadable PDF counts as one page, which then fails to render and is logged.
                info = subprocess.run(["pdfinfo", path], capture_output=True, text=True, errors="replace").stdout
                count = re.search(r"^Pages:\s*(\d+)", info, re.MULTILINE)
                document_pages += [(f"{name} page {page + 1}", path, name, page)
                                   for page in range(int(count[1]) if count else 1)]
            else:
                document_pages.append((name, path, name, None))
        pages += [(label, (document, order, path, name, page))
                  for order, (label, path, name, page) in enumerate(document_pages)]
    for label, arguments in pages:
        try:
            create_page(*arguments)
        except Exception as error:
            print(f"Import failed: {label}: {error!r}", file=sys.stderr)


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
