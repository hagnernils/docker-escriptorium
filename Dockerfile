FROM python:3.12-slim-bookworm

ARG ESCRIPTORIUM_VERSION=26.04.1
# Select CUDA 12.6 wheels by default; override the index for CPU builds.
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126
ARG TORCH_VERSION=2.7.1
ARG TORCHVISION_VERSION=0.22.1

ENV POSTGRES_DB=escriptorium \
    POSTGRES_USER=escriptorium \
    POSTGRES_PASSWORD=escriptorium \
    SQL_PORT=5432

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev libxml2-dev libxslt-dev zlib1g-dev \
    libffi-dev libssl-dev git curl \
    libleptonica-dev libvips default-jdk ant \
    redis postgresql postgresql-contrib tesseract-ocr supervisor nginx && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN addgroup --system uwsgi && \
    adduser --system --no-create-home --ingroup uwsgi uwsgi && \
    useradd -ms /bin/bash escriptorium

WORKDIR /home/escriptorium

RUN git clone --depth 1 --branch "$ESCRIPTORIUM_VERSION" \
        https://gitlab.com/scripta/escriptorium.git

RUN pip install --upgrade pip --no-cache-dir && \
    pip install --no-cache-dir \
        "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VERSION" \
        --index-url "$TORCH_INDEX_URL" && \
    pip install --no-cache-dir -r ./escriptorium/app/requirements.txt && \
    pip install --no-cache-dir flower gunicorn

RUN cd ./escriptorium/front && \
    npm ci && \
    npm run production && \
    rm -rf node_modules && \
    cd .. && rm -rf .git

RUN chown -R escriptorium:escriptorium /home/escriptorium/escriptorium

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY django-init.sh /django-init.sh
COPY docker-entrypoint.sh /usr/local/bin/
COPY nginx.conf /etc/nginx/sites-available/default

RUN chmod +x /django-init.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 80 5555

CMD ["docker-entrypoint.sh"]
