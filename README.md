# Escriptorium interactive tool for galaxy 

Packaging [eScriptorium](https://gitlab.com/scripta/escriptorium) as a docker container with additional files needed for it to work as interactive tool.

The image uses eScriptorium **26.04.1**, Python **3.12**, PyTorch **2.7.1**, and Torchvision **0.22.1**. Passim/PySpark text alignment is excluded and disabled with `TEXT_ALIGNMENT=False` (to reduce container size). Two stages for the build allow the removal of frontend-build dependencies.

To build a CPU image (only when cpu; 
```sh
docker build --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu -t localhost/escriptorium:26.04.1-cpu . 
```
Leave out `--build-arg` line for default cuda 12.6 pytorch. GPU execution requires a compatible NVIDIA driver and the NVIDIA Container Toolkit configured for Docker on the host.

## Run image without galaxy

Start the cpu image with ports bound to localhost (8080 for escriptorium and 5555 for flower, the celery worker dashboard):
```sh
docker run --detach --name escriptorium \
  --cpus=4 --memory=12g --pids-limit=256 \
  --publish 127.0.0.1:8080:80 \
  --publish 127.0.0.1:5555:5555 \
  escriptorium:26.04.1-cpu
```

For GPU usage, add `--gpus all --env KRAKEN_TRAINING_DEVICE=cuda:0` (or `--device nvidia.com/gpu=all` for podman).

Any escriptorium projects and media files you might change or upload live in the container's writable layer, they survive `docker stop`/`docker start`, but are lost when the container is removed with `docker rm`.

The image contains an initialized PostgreSQL database with the application migrations applied, and collected static assets. Each new container starts with its own copy of that database. Database storage and credentials are internal to the container; rebuild the image to update the schema or static assets. Run with the image's database settings and directories rather than mounting database or static directories.

Supervisor starts directly as the image command. Check services with `docker logs --follow escriptorium` and `docker exec escriptorium supervisorctl status`, then open <http://localhost:8080>.

## Run as Galaxy interactive tool

The `galaxy/` folder containes the files needed to run the docker container as interactive tool. 
- `interactivetool_escriptorium.xml`: tool wrapper. Links the inputs into `inputs/` of the job directory and runs `start.sh`.
- `start.sh`: starts Supervisor, waits up to 120 seconds for services, creates the session user, project and documents, and uploads the inputs through the eScriptorium REST API. Each Galaxy invocation uses a fresh container. Stopping the script also stops Supervisor.
- `galaxy_settings.py`: settings overlay for the Galaxy domain.
- `galaxy_urls.py`: the `/galaxy/login/` entry point that signs in the escriptorium user.

### Galaxy configuration

The container runs as root because Supervisor starts PostgreSQL and the services under their own users. So the we need the following config for galaxy:

- `galaxy.yml`: `interactivetools_enable: true`, `interactivetools_map`, `galaxy_infrastructure_url`,
  `outputs_to_working_directory: true`, and the Gravity `gx_it_proxy` enabled.
- `job_conf.yml`: a destination with `docker_enabled: true`, an empty `docker_set_user`, `require_container: true`,
  and `docker_cmd: podman` when using Podman. Galaxy sets `HOME` to the job directory, so rootless Podman also needs
  an `env` entry `CONTAINERS_STORAGE_CONF` pointing at a `storage.conf` whose `graphroot` is the user's image storage
  (`~/.local/share/containers/storage`).
- `tool_conf.xml`: `<tool file="interactive/escriptorium/interactivetool_escriptorium.xml" />`.
