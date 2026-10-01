#!/bin/bash

chown escriptorium:escriptorium /home/escriptorium/escriptorium/app/media
exec /usr/bin/supervisord -n
