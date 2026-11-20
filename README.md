# Escriptorium interactive tool for galaxy

Packaging [eScriptorium](https://gitlab.com/scripta/escriptorium) as a docker container with additional files needed for it to work as interactive tool.

The image uses eScriptorium **26.04.1**, Python **3.12** and is built in two stages for the build allow the removal of build-only and unneeded (e.g. Java for disabled text alignment) dependencies.

To build a CPU image:
```sh
docker build --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu -t localhost/escriptorium:26.04.1-cpu . 
```
Leave out `--build-arg` line for default cuda 12.6 pytorch. GPU execution requires a compatible NVIDIA driver and the NVIDIA Container Toolkit configured for Docker on the host.

## Run image without galaxy

Start the cpu image with ports bound to localhost (8080 for escriptorium and 5555 for flower, the celery worker dashboard):
```sh
docker run --detach --name escriptorium \
  --cpus=12 --memory=12g --pids-limit=256 --env OMP_NUM_THREADS=12 \
  --publish 127.0.0.1:8080:80 \
  --publish 127.0.0.1:5555:5555 \
  localhost/escriptorium:26.04.1-cpu
```
`--cpus` bounds the CPU use of the container, and `OMP_NUM_THREADS` the PyTorch threads of each task, which otherwise default to one per host CPU and can exhaust the pids limit on large hosts. The `celery-cpu` worker runs up to 4 segmentation or transcription tasks at once, `celery-low` runs imports and thumbnails one at a time in order, and `celery-gpu` runs one training at a time. OpenBLAS, libvips and nginx are limited to one thread or worker.

For GPU usage, add `--gpus all --env KRAKEN_TRAINING_DEVICE=cuda:0` (or `--device nvidia.com/gpu=all` for podman).

Any escriptorium projects and media files you might change or upload live in the container's writable layer, they survive `docker stop`/`docker start`, but are lost when the container is removed with `docker rm`.

The image contains an initialized PostgreSQL database with the application migrations applied, and collected static assets. Each new container starts with its own copy of that database. Database storage and credentials are internal to the container; rebuild the image to update the schema or static assets. Run with the image's database settings and directories rather than mounting database or static directories.

Supervisor starts directly as the image command. Check services with `docker logs --follow escriptorium` and `docker exec escriptorium supervisorctl status`, then open <http://localhost:8080>.

## Run as Galaxy interactive tool

The `galaxy/` folder is copied into the image at `/home/escriptorium/galaxy`, so `interactivetool_escriptorium.xml` is the only file Galaxy needs. Galaxy starts the container with `--cpus` set to the job's slots (`local_slots` for the local runner).
- `interactivetool_escriptorium.xml`: the tool. Galaxy writes its inputs as JSON (`<configfiles><inputs>`) and runs `start.sh` with that file.
- `start.sh`: the startup script for the container: it sets the PyTorch threads to the Galaxy slots, starts Supervisor, runs `copy_inputs.py` as root, waits up to 120 seconds for the db to be ready, then runs `populate.py` to import inputs as the escriptorium user. Stopping the script also stops Supervisor cleanly.
- `copy_inputs.py`: copies the galaxy datasets to where the escriptorium user can read them
- `populate.py`: creates the escriptorium user, the default "Galaxy" project and one document per Document input block. PDF pages are directly rendered and imported int oescriptoriums db so they get automatically added to the project, models are imported with automatic model type detection.
- `galaxy_settings.py`: settings overlay for the Galaxy domain.
- `galaxy_urls.py`: the `/galaxy/login/` entry point that signs in the eScriptorium user.

Outputs: TODO
- Galaxy collects any files from the media/ folder of the tool directory

### Galaxy configuration

The container runs as root because Supervisor starts PostgreSQL and the services under their own users. So then we need the following config for galaxy:

- `galaxy.yml`: `interactivetools_enable: true`, `interactivetools_map`, `galaxy_infrastructure_url`,
  `outputs_to_working_directory: true`, and the Gravity `gx_it_proxy` enabled.
- `job_conf.yml`: a destination with `docker_enabled: true`, an empty `docker_set_user`, `require_container: true`,
  and `docker_cmd: podman` when using Podman. Galaxy sets `HOME` to the job directory, so rootless Podman also needs
  an `env` entry `CONTAINERS_STORAGE_CONF` pointing at a `storage.conf` whose `graphroot` is the user's image storage
  (`~/.local/share/containers/storage`).
- `tool_conf.xml`: `<tool file="interactive/escriptorium/interactivetool_escriptorium.xml" />`.
