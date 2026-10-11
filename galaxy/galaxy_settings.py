# eScriptorium settings to run as Galaxy interactive tool
import os
from urllib.parse import urlsplit

from escriptorium.settings import *  # noqa: F401,F403

ROOT_URLCONF = "galaxy_urls"

# Galaxy serves the session on a subdomain of its own host:
# https://<id>.interactivetool.<galaxy-host>.
# http://3eceq7lozr0y6-2wtdzgq6hr76f.ep.interactivetool.localhost:4002/galaxy/login/
# With this django can trust requests coming from that origin.
galaxy_url = urlsplit(os.environ["GALAXY_URL"])
CSRF_TRUSTED_ORIGINS = [f"{galaxy_url.scheme}://*.{galaxy_url.netloc}"]
SESSION_COOKIE_SECURE = CSRF_COOKIE_SECURE = galaxy_url.scheme == "https"
