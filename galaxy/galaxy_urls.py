"""eScriptorium URLs plus the Galaxy entry point that logs in the session user."""
import os

from django.contrib.auth import get_user_model, login
from django.http import HttpResponse
from django.shortcuts import redirect
from django.urls import path

from core.models import Document
from escriptorium.urls import urlpatterns as escriptorium_urlpatterns

STARTING_PAGE = '<meta http-equiv="refresh" content="5">eScriptorium is starting, this page reloads automatically.'


def galaxy_login(request):
    """Galaxy's proxy already restricts this session to its owner, so the mapped user is logged in directly."""
    user = get_user_model().objects.filter(username=f"galaxy_{os.environ['GALAXY_USER_ID']}").first()
    document = Document.objects.filter(owner=user).first() if user else None
    if document is None:
        return HttpResponse(STARTING_PAGE)
    login(request, user, backend="django.contrib.auth.backends.ModelBackend")
    return redirect("document-images", pk=document.pk)


urlpatterns = [path("galaxy/login/", galaxy_login)] + escriptorium_urlpatterns
