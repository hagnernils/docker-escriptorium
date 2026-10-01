# docker-escriptorium-hagner

Container packaging [eScriptorium](https://gitlab.com/scripta/escriptorium),
an application for document segmentation, transcription, and handwriting
recognition.

## Versions and builds

The image uses eScriptorium **26.04.1**, Python **3.12**, PyTorch **2.7.1**,
and Torchvision **0.22.1**. Passim/PySpark text alignment is excluded
and disabled with `TEXT_ALIGNMENT=False` to reduce container size.
A multi-stage build keeps compilers and frontend build dependencies away from the final image.

Run these commands from the repository root with Docker (or alias docker=podman). Build a CPU image:

```sh
docker build \
  --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu \   # <- only when cpu; leave out line for default cuda 12.6 pytorch
  -t escriptorium:26.04.1-cpu . # use any tag you wish, build here (.)
```

GPU execution requires a compatible NVIDIA driver and the NVIDIA Container Toolkit configured for Docker on the host.

## Run image with persistent volumes

To run the application from the image we need to create named volumes for the database and uploaded media,
then start the image with ports bound to localhost. The image initializes its local database
using the service defaults configured in the startup scripts (django-init.sh).

```sh
docker volume create escriptorium-db
docker volume create escriptorium-media
docker run --detach --name escriptorium \
  --cpus=4 --memory=12g --pids-limit=256 \
  --env PGSSLCERT=/tmp/postgresql.crt \
  --publish 127.0.0.1:8080:80 \ # port for escriptorium
  --publish 127.0.0.1:5555:5555 \ # port for flower, the celery worker dashboard
  --volume escriptorium-db:/var/lib/postgresql \
  --volume escriptorium-media:/home/escriptorium/escriptorium/app/media \
  escriptorium:26.04.1-cpu  # use the cpu version
```

For GPU execution, use `escriptorium:26.04.1` and add `--gpus all --env KRAKEN_TRAINING_DEVICE=cuda:0`
(or `--device nvidia.com/gpu=all` for podman) before the image name. The volumes retain database and media contents across container restarts.

You can check startup with `docker logs --follow escriptorium` and
`docker exec escriptorium supervisorctl status`. Wait for `django-init` to
complete migrations and static-file collection before creating an account.
Its successful `EXITED` state is expected; other services should be `RUNNING`.
Initialization output is in `/var/log/escriptorium.log` inside the container.

## Create an eScriptorium superuser account

Create an eScriptorium superuser account with administrative access, choosing
its username, email, and password interactively:

```sh
docker exec -it --user escriptorium \
  --workdir /home/escriptorium/escriptorium/app \
  escriptorium python manage.py createsuperuser
```

Open eScriptorium at <http://localhost:8080> and sign in with that account.
Flower, the task monitor, is available at <http://localhost:5555>.
