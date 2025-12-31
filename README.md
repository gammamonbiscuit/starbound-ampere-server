# Biscuit's Starbound ARM Dedicated Server Docker
This is my attempt on running Starbound dedicated server in an Oracle Ampere A1 Compute instance, with OpenStarbound and Steam workshop mod support.

>[!WARNING]
>No docker image is available for download, you have to build it yourself,
>I made this only to let myself host Starbound in this very specific instance and play with my friends,
>I **do not** guarantee that this will work on your machine.
>**No support will be provided!**

## Build
```bash
docker build -t starbound-ampere-server:local .
```
>[!NOTE]
>This will take a long time to compile, about 33 minutes on my 4-core VM.Standard.A1.Flex instance. When building for `linux/amd64` it just downloads OpenStarbound's [release assets](https://github.com/OpenStarbound/OpenStarbound/releases), if an `linux/arm64` build becomes available from them in the future, I will use that too instead of compiling everything.

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
      - ~/.starbound-backup:/server/backup
      - ~/.starbound-data:/server/data
    restart: unless-stopped
```

This [docker-compose.yml](/docker-compose.yml) example only mounts some user serviceable paths, but if you have more needs, here are some info about the `/server` directory:

| Container Path | Info |
|:----|:----|
| /server/starbound.sh        | Main script                                                |
| /server/data/starbound.env  | Environment variables controlling the script’s behaviour   |
| /server/steamcmd            | SteamCMD and everything used by it                         |
| /server/starbound/mods      | All .pak mods and workshop mod symlinks                    |
| /server/starbound/storage   | Save files                                                 |
| /server/starbound/linux     | Starbound’s dedicated server program                       |
| /server/starbound/assets    | Starbound’s packed.pak                                     |
| /server/starbound/steamapps | Workshop mods                                              |
| /server/openstarbound       | Pre-compiled OpenStarbound ARM build                       |
| /server/backup              | Backup data                                                |

## Steam Guard and packed.pak
You do not need to disable Steam Guard if you have mobile authenticator enabled. Steam will use an interactive notification in the app to let you proceed with the login request, it might ask you few more questions if you are logging in from an unusual location, for example, a VPS in another country.

With OpenStarbound being the default game engine used in this image, you do not need to login to Steam to download vanilla Starbound, but the `packed.pak` that comes with it is still a problem. To solve this you can use the `packed.pak` from the Starbound copy you own, bind `/server/starbound/assets` to host and put `packed.pak` inside to eliminate the need of Steam login.

It can be found in the following locations, it is recommended to copy from dedicated server, it contains the minimal needed files for server to operate.

`[Steam Root]/steamapps/common/Starbound Dedicated Server/assets/packed.pak`

The one from client also works.

`[Steam Root]/steamapps/common/Starbound/assets/packed.pak`


## Environment Variables
These variables should be modified in `starbound.env` instead of `docker-compose.yml` because the main script will read them from `starbound.env` at runtime, if you still prefer that you can place an empty `starbound.env` to bypass re-creation.

| Variable | Default | Example | Info |
|:----|:----|:----|:----|
| `STEAM_LOGIN`           | `"anonymous"` | `"myusername mypassword"` | Your Steam credentials, required to download the game, workshop mods are always downloaded anonymously.                                                               |
| `OPENSTARBOUND`         | `true`        | `false`                   | To use OpenStarbound instead of vanilla Starbound, however you still have to use Steam to download (or provide your own copy of) `packed.pak` .                       |
| `LAUNCH_GAME`           | `true`        | `false`                   | Starbound will be launched after all update operations (if any) are finished.                                                                                         |
| `BACKUP_ENABLED`        | `true`        | `false`                   | Backup save data on start, before any update and game launch.                                                                                                         |
| `BACKUP_VERSIONS`       | `10`          | `5`                       | Decides how many copies of backup data will be kept.                                                                                                                  |
| `BACKUP_COOLDOWN`       | `1800`        | `3600`                    | Number of seconds that must be passed before a backup task can run again, this is to prevent backups being overwritten by broken repeatedly restarting container.     |
| `BACKUP_MODS_MANUAL`    | `false`       | `true`                    | Include manual mods in backup.                                                                                                                                        |
| `BACKUP_MODS_WORKSHOP`  | `false`       | `true`                    | Include workshop mods in backup.                                                                                                                                      |
| `UPDATE_STEAM`          | `false`       | `true`                    | Decides whether to update SteamCMD or not, if `UPDATE_GAME` or `UPDATE_WORKSHOP` is set to true this option will be ignored.                                          |
| `UPDATE_GAME`           | `false`       | `true`                    | Decides whether to update all game files or not, if `LAUNCH_GAME` is set to `true` and the game is incomplete, this script will still re-download the missing parts.  |
| `UPDATE_WORKSHOP`       | `false`       | `true`                    | Decides whether to update workshop mods or not, whilst skipping already installed mods.                                                                               |
| `UPDATE_WORKSHOP_FORCE` | `false`       | `true`                    | Changes `UPDATE_WORKSHOP` behaviour to verify and download every workshop mods if needed.                                                                             |
| `WORKSHOP_ITEMS`        |               | `1115920474,729427436`    | A list of Steam workshop ids of individual mods, the id can be obtained from the URL of the item page.                                                                |
| `WORKSHOP_COLLECTIONS`  |               | `3468099241`              | A list of Steam workshop ids, but only for collections.                                                                                                               |
| `WORKSHOP_CHUNK`        | `20`          | `0`                       | Workshop mods are downloaded in groups to avoid downloading a huge list all at once, this option decides the group size, set to `0` to turn off.                      |
| `WORKSHOP_PRUNE`        | `true`        | `false`                   | Delete workshop mods that are no longer included in `WORKSHOP_ITEMS` or `WORKSHOP_COLLECTIONS`.                                                                       |
| `WORKSHOP_MAX_RETRY`    | `3`           | `5`                       | Number of retries should be performed when there are errors downloading mods, container will exit after all retries are exhausted.                                    |

## Credits
Starbound

https://store.steampowered.com/app/211820/Starbound/

OpenStarbound

https://github.com/OpenStarbound/OpenStarbound

...and to compile OpenStarbound for ARM

https://github.com/OpenStarbound/OpenStarbound/pull/263

Box64

https://github.com/ptitSeb/box64
