"""eScriptorium settings for a Galaxy interactive tool session."""
import os
from urllib.parse import urlsplit

from escriptorium.settings import *  # noqa: F401,F403

ROOT_URLCONF = "galaxy_urls"

# Galaxy serves the session on a subdomain of its own host, e.g. https://<id>.interactivetool.<galaxy-host>.
galaxy_url = urlsplit(os.environ["GALAXY_URL"])
CSRF_TRUSTED_ORIGINS = [f"{galaxy_url.scheme}://*.{galaxy_url.netloc}"]
SESSION_COOKIE_SECURE = CSRF_COOKIE_SECURE = galaxy_url.scheme == "https"
