# Biscuit's Starbound ARM Dedicated Server Docker
This is my attempt on running Starbound dedicated server in an Oracle Ampere A1 Compute instance, with Steam workshop mod support.

>[!WARNING]
>No docker image is available for download, you have to build it yourself,
>I made this only to let myself host Starbound in this very specific instance and play with my friends,
>I **do not** guarantee that this will work on your machine.
>**No support will be provided!**

## Build
```bash
docker build -t starbound-ampere-server:local .
```

## Docker Compose
```yml
services:
  starbound:
    image: starbound-ampere-server:local
    pull_policy: never
    container_name: starbound
    user: 1000:1000
    ports: [21025:21025/tcp]
    volumes:
      - ~/.starbound-mods:/server/starbound/mods
      - ~/.starbound-storage:/server/starbound/storage
      - ~/starbound.env:/server/starbound.env
    restart: unless-stopped
```

This [docker-compose.yml](/docker-compose.yml) example only mounts some user serviceable paths, but if you have more needs, here are some info about the `/server` directory:
| Container Path | Info |
|:----|:----|
| /server/starbound.sh        | Main script                                                |
| /server/starbound.env       | Environment variables controlling the script’s behaviour   |
| /server/steamcmd            | SteamCMD and everything used by it                         |
| /server/starbound/mods      | All .pak mods and workshop mod symlinks                    |
| /server/starbound/storage   | Save files                                                 |
| /server/starbound/linux     | Starbound’s dedicated server program                       |
| /server/starbound/assets    | Starbound’s packed.pak                                     |
| /server/starbound/steamapps | Workshop mods                                              |

## Environment Variables
| Variable | Default | Example | Info |
|:----|:----|:----|:----|
| `STEAM_LOGIN`           | `"anonymous"` | `"myusername mypassword"` | Your Steam credentials, required to download the game, workshop mods are always downloaded anonymously.                                          |
| `LAUNCH_GAME`           | `true`        | `false`                   | Starbound will be launched after all update operations (if any) are finished.                                                                    |
| `UPDATE_GAME`           | `false`       | `true`                    | Decides whether to update Starbound or not, if `LAUNCH_GAME` is set to `true` and the game is not found, this option will be ignored.            |
| `UPDATE_WORKSHOP`       | `false`       | `true`                    | Decides whether to update workshop mods or not, whilst skipping already installed mods.                                                          |
| `UPDATE_WORKSHOP_FORCE` | `false`       | `true`                    | Changes `UPDATE_WORKSHOP` behaviour to verify and download every workshop mods if needed.                                                        |
| `WORKSHOP_ITEMS`        |               | `1115920474,729427436`    | A list of Steam workshop ids of individual mods, the id can be obtained from the URL of the item page.                                           |
| `WORKSHOP_COLLECTIONS`  |               | `3468099241`              | A list of Steam workshop ids, but only for collections.                                                                                          |
| `WORKSHOP_CHUNK`        | `20`          | `0`                       | Workshop mods are downloaded in groups to avoid downloading a huge list all at once, this option decides the group size, set to `0` to turn off. |
| `WORKSHOP_PRUNE`        | `true`        | `false`                   | Delete workshop mods that are no longer included in `WORKSHOP_ITEMS` or `WORKSHOP_COLLECTIONS`.                                                  |
| `WORKSHOP_MAX_RETRY`    | `3`           | `5`                       | Number of retries should be performed when there are errors downloading mods, container will exit after all retries are exhausted.               |
