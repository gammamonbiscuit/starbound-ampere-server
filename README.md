# Starbound Ampere Server
This is my attempt on running Starbound dedicated server in an Oracle Ampere A1 Compute instance.

>[!WARNING]
>This project is having major ongoing changes, contents in this README are outdated.

>[!WARNING]
>No docker image is available for download, you have to build it yourself,
>I made this only to let myself host Starbound in this very specific instance and play with my friends,
>I **do not** guarantee that this will work on your machine.
>**No support will be provided!**

## Features
1. Multi-arch Starbound dedicated server
     - OpenStarbound `>=0.1.15` has native arm64 support, older versions before that are compiled from source.
     - There are proberly hundreds of projects out there that can do this, if you only want a simple x86 server, theirs might be a better choice.
2. Use manual mods (`*.pak`)
     - Native feature of Starbound, not much to talk about.
     - You can use unpacked mods, but this script only handles the backup of `*.pak` files, be aware if you want to include mods in your backup.
3. Use Steam workshop mods
     - Another common feature of similar projects...
     - This is achieved by using steamcmd’s `workshop_download_item` command, and then the script creates symlink to let the game read them.
4. Use Steam workshop collection mods
     - Very convenient if you use workshop collections to manage your mods, you can even combine multiple collections.
     - The script uses Steamworks web API `ISteamRemoteStorage/GetCollectionDetails` to get workshop item ids from the collection ids you provided.
5. Backup data at launch
     - Backups your universe into a `*.zip` file before starting the server, useful if you accidentally dropped a nuke in your base.
     - Able to keep multiple versions, what if this is combined with some external script handling auto server restart...

## How to run a server
1. Clone this repo
```bash
git clone https://github.com/gammamonbiscuit/starbound-ampere-server.git
```
2. Go into the repo's directory
```bash
cd starbound-ampere-server
```

3. Build docker image
```bash
docker build -t starbound-ampere-server:local .
```

>[!NOTE]
>This will build box64 from source and might take some time. For OpenStarbound, version `0.1.15` and onwards are already native arm64, so unless you want an old version, the script will just download the release build from github. Compile time is about half an hour on my 4-core VM.Standard.A1.Flex instance, or 15-20 minutes on Apple M4 depending on how fast I can download vcpkg.

4. Optional: Copy the example configs
```bash
cp ./data/config/config.env.example ./data/config/config.env
cp ./data/config/sbinit.config.example ./data/config/sbinit.config
```

5. Start the server
```bash
docker compose up
```

## Docker Compose and directory structure
```yml
services:
  starbound:
    image: starbound-ampere-server:local
    pull_policy: never
    container_name: starbound
    user: 1000:1000
    ports: [21025:21025/tcp]
    volumes:
      - ./data:/data
    stop_grace_period: 1m
    restart: unless-stopped
```

This [compose.yml](/compose.yml) example only mounts the user serviceable `/data`, but if you have more needs, here's the directory tree inside the container:

```text
/data
├── asset
│   └── packed.pak                   # Starbound's retail asset
├── backup              
│   └── universe_*.zip               # Backup data
├── config
│   ├── config.env                   # Container's config file
│   ├── sbinit.config                # Starbound's config file
│   └── workshop_data.json           # Workshop mod data, not for edit
├── mods
│   ├── *.pak                        # Manual mods
│   ├── workshop-*-*.pak             # Workshop mod symlinks
├── steam
│   ├── home                         # Container user's home
│   ├── steamapps                    # Actual storage of workshop mods
│   └── steamcmd                     # SteamCMD binaries
└── storage
    ├── logs
    │   └── starbound_server.log.*   # Rotated logs from provious sessions
    ├── starbound_server.log         # Live log
    └── universe                     # Your universe

/server
|-- osb                              # OpenStarbound binaries
└── starbound.sh                     # Main script
```

## Steam Guard and packed.pak
You do not need to disable Steam Guard if you have mobile authenticator enabled. Steam will use an interactive notification in the app to let you proceed with the login request, it might ask you few more questions if you are logging in from an unusual location, for example, a VPS in another country.

With OpenStarbound being the default game engine used in this image, you do not need to login to Steam to download vanilla Starbound, but the `packed.pak` that comes with it is still a problem. To solve this you can use the `packed.pak` from the Starbound copy you own, put `packed.pak` in `/data/asset` to eliminate the need of Steam login.

It can be found in the following locations, it is recommended to copy from dedicated server, it contains the minimal needed files for server to operate.

`[Steam Root]/steamapps/common/Starbound Dedicated Server/assets/packed.pak`

The one from client also works.

`[Steam Root]/steamapps/common/Starbound/assets/packed.pak`


## Environment Variables
These variables should be modified in `config.env` instead of `compose.yml` because the main script will read them from `config.env` at runtime, if you still prefer that you can place an empty `config.env` to bypass re-creation.

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
| `WORKSHOP_ITEMS`        |               | `1115920474,729427436`    | A list of Steam workshop ids of individual mods, the id can be obtained from the URL of the item page.                                                                |
| `WORKSHOP_COLLECTIONS`  |               | `3468099241`              | A list of Steam workshop ids, but only for collections.                                                                                                               |
| `WORKSHOP_CHUNK`        | `20`          | `0`                       | Workshop mods are downloaded in groups to avoid downloading a huge list all at once, this option decides the group size, set to `0` to turn off.                      |
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
