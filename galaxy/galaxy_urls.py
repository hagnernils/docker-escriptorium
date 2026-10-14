"""eScriptorium URLs plus the Galaxy entry point that logs in the session user."""
import os

from django.contrib.auth import get_user_model, login
from django.db import DatabaseError
from django.http import HttpResponse
from django.shortcuts import redirect
from django.urls import path

from core.models import Document
from escriptorium.urls import urlpatterns as escriptorium_urlpatterns

STARTING_PAGE = '<meta http-equiv="refresh" content="5">eScriptorium is starting, this page reloads automatically.'


def galaxy_login(request):
    """Galaxy's proxy already restricts this session to its owner, so the mapped user is logged in directly."""
    try:
        user = get_user_model().objects.filter(username=f"galaxy_{os.environ['GALAXY_USER_ID']}").first()
        documents = list(Document.objects.filter(owner=user).select_related("project")) if user else []
    except DatabaseError:  # The database is still being migrated.
        documents = []
    if not documents:
        return HttpResponse(STARTING_PAGE)
    login(request, user, backend="django.contrib.auth.backends.ModelBackend")
    if len(documents) == 1:
        return redirect("document-images", pk=documents[0].pk)
    return redirect("documents-list", slug=documents[0].project.slug)


urlpatterns = [path("galaxy/login/", galaxy_login)] + escriptorium_urlpatterns
