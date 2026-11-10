#!/bin/bash
echo "⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐"
echo "   Starbound Ampere Server   "
echo "⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐"

DIR_SERVER_ROOT="${DIR_SERVER_ROOT:-/server}"
DIR_DATA_ROOT="${DIR_DATA_ROOT:-/data}"
DIR_WORKSHOP_CONTENT="${DIR_DATA_ROOT}/steam/steamapps/workshop/content/211820"
HOME="${DIR_DATA_ROOT}/steam/home"

PATH_CONFIG_ENV="${DIR_DATA_ROOT}/config/config.env"
PATH_CONFIG_SBINIT="${DIR_DATA_ROOT}/config/sbinit_defaults.config"
PATH_CONFIG_WS="${DIR_DATA_ROOT}/config/workshop_data.json"
PATH_LOG="${DIR_DATA_ROOT}/container.log"

echo "🚧 Permission check"
PERMISSION_CHECK=("${DIR_DATA_ROOT}"
                  "${DIR_DATA_ROOT}/asset"
                  "${DIR_DATA_ROOT}/backup"
                  "${DIR_DATA_ROOT}/config"
                  "${DIR_DATA_ROOT}/mods"
                  "${DIR_DATA_ROOT}/steam"
                  "${DIR_DATA_ROOT}/storage"
                  "${HOME}"
                 )
for LOOP_PERMISSION_CHECK in "${PERMISSION_CHECK[@]}"; do
    if [[ -d $LOOP_PERMISSION_CHECK ]]; then
        if ! [[ -r $LOOP_PERMISSION_CHECK && -w $LOOP_PERMISSION_CHECK && -x $LOOP_PERMISSION_CHECK ]]; then
            echo "  ❌ $LOOP_PERMISSION_CHECK is not accessable by $(id -u):$(id -g), paused until this is resolved."
            until [[ -r $LOOP_PERMISSION_CHECK && -w $LOOP_PERMISSION_CHECK && -x $LOOP_PERMISSION_CHECK ]]; do
                stat -c "    ❌ Current permission of [$LOOP_PERMISSION_CHECK]: %A(%a) %U(%u) %G(%g)" $LOOP_PERMISSION_CHECK
                sleep 5
            done
        fi
        echo "  ✔️ $LOOP_PERMISSION_CHECK"
    else
        echo "  ✔️ $LOOP_PERMISSION_CHECK (Not exist yet)"
    fi
done

CONTAINER_ABORT() {
    echo "❌ ABORT: $*" >&2
    exit 1
}

mkdir -m 755 -p ${DIR_DATA_ROOT}/{asset,backup,config,mods,steam/home,storage} || CONTAINER_ABORT "Failed to create data directories..."
echo "🚧 Logging started" | tee "$PATH_LOG"
{
if [[ ! -f "${PATH_CONFIG_ENV}" ]]; then
    echo "🚧 Creating config file..."
    tee "${PATH_CONFIG_ENV}" <<EOF >/dev/null
# Your Steam credentials, required to download the game, workshop mods are always downloaded anonymously.
# Default: "anonymous"
# Example: "myusername mypassword"
STEAM_LOGIN="$STEAM_LOGIN"

# Use OpenStarbound instead of the original binaries, however you still have to login to Steam to download the assets.
# Default: true
OPENSTARBOUND=$OPENSTARBOUND

# Starbound will be launched after all update operations (if any) are finished.
# Default: true
LAUNCH_GAME=$LAUNCH_GAME

# Backup save data on start, before any update and game launch.
# Default: true
BACKUP_ENABLED=$BACKUP_ENABLED

# Decides how many copies of backup data will be kept.
# Default: 10
BACKUP_VERSIONS=$BACKUP_VERSIONS

# Number of seconds that must be passed before a backup task can run again, this is to prevent backups being overwritten by broken repeatedly restarting container.
# Default: 1800
BACKUP_COOLDOWN=$BACKUP_COOLDOWN

# Include manual mods in backup.
# Default: false
BACKUP_MODS_MANUAL=$BACKUP_MODS_MANUAL

# Include workshop mods in backup.
# Default: false
BACKUP_MODS_WORKSHOP=$BACKUP_MODS_WORKSHOP

# Decides whether to update SteamCMD or not, if UPDATE_GAME or UPDATE_WORKSHOP is set to true this option will be ignored.
# Default: false
UPDATE_STEAM=$UPDATE_STEAM

# Decides whether to update all game files or not, if LAUNCH_GAME is set to true and the game is incomplete, this script will still re-download the missing parts.
# Default: false
UPDATE_GAME=$UPDATE_GAME

# Decides whether to update workshop mods or not, whilst skipping already installed mods.
# Default: false
UPDATE_WORKSHOP=$UPDATE_WORKSHOP

# A list of Steam workshop ids of individual mods, the id can be obtained from the URL of the item page,
# the following URL has the id of 1115920474, this is what we needed.
# https://steamcommunity.com/workshop/filedetails/?id=1115920474
# Default: (empty)
# Example: 1115920474,729427436
WORKSHOP_ITEMS=$WORKSHOP_ITEMS

# A list of Steam workshop ids, but only for collections.
# Default: (empty)
# Example: 3468099241
WORKSHOP_COLLECTIONS=$WORKSHOP_COLLECTIONS

# Workshop mods are downloaded in groups to avoid downloading a huge list all at once, this option decides the group size, set to 0 to turn off.
# Default: 20
WORKSHOP_CHUNK=$WORKSHOP_CHUNK

# Number of retries should be performed when there are errors downloading mods, container will exit after all retries are exhausted.
# Default: 3
WORKSHOP_MAX_RETRY=$WORKSHOP_MAX_RETRY

EOF
else
    echo "🚧 Reading config file..."
    source "${PATH_CONFIG_ENV}"
fi

if [[ ! -f "${PATH_CONFIG_SBINIT}" ]]; then
    echo "🚧 Creating sbinit template file..."
    tee "${PATH_CONFIG_SBINIT}" <<EOF >/dev/null
{
    "assetDirectories": [],
    "defaultConfiguration": {
        "allowAssetsMismatch": true,
        "gameServerBind": "*",
        "maxTeamSize": 64,
        "queryServerBind": "*",
        "rconServerBind": "*"
    },
    "includeUGC": false,
    "storageDirectory": ""
}
EOF
fi

# Decide how to run programs.
if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then
    RUNNER='./'
    echo "🚧 x86"
else
    RUNNER='box64 '
    echo "🚧 arm64, ${RUNNER}"
fi

if [[ ${OPENSTARBOUND,,} == true ]]; then
    echo "🎮 OpenStarbound selected."
    echo "🎮 https://github.com/OpenStarbound/OpenStarbound"
else
    echo "🎮 Official Steam verison selected."
    echo "🎮 https://store.steampowered.com/app/211820/Starbound/"
fi

# Backup save data on start.
if [[ ${BACKUP_ENABLED,,} == true ]]; then
    echo "💾 Backup enabled."
    BACKUP_LATEST=$(find "${DIR_DATA_ROOT}/backup" -type f | grep -E "\/universe_[0-9]{10}.zip$" | sort -r | head -1 | sed -r "s/.*\/universe_([0-9]{10}).zip$/\1/g")
    BACKUP_COOLNESS=$(($(date +%s) - ${BACKUP_LATEST:-0}))
    if [[ $BACKUP_COOLNESS -lt $BACKUP_COOLDOWN ]]; then
        echo "  ❌ There are archive(s) younger than $BACKUP_COOLDOWN seconds ($BACKUP_COOLNESS s), skipping backup task."
    else
        BACKUP_NEWFILE="${DIR_DATA_ROOT}/backup/universe_$(date +%s).zip"
        pushd ${DIR_DATA_ROOT} > /dev/null
        echo "  📁 Save file"
        zip $BACKUP_NEWFILE -9or "./storage" -x "*/starbound_server.log.*"
        if [[ ${BACKUP_MODS_MANUAL,,} == true ]]; then
            echo "  📁 Manual mods"
            zip $BACKUP_NEWFILE -9uor "./mods" -i "*.pak" -x "*/workshop-*.pak"
        fi
        if [[ ${BACKUP_MODS_WORKSHOP,,} == true ]]; then
            echo "  📁 Workshop mods"
            zip $BACKUP_NEWFILE -9uor "./mods" -i "*/workshop-*.pak"
        fi
        popd > /dev/null
        echo "  ✔️ $(du -shb ${BACKUP_NEWFILE})"
        find "${DIR_DATA_ROOT}/backup" -type f | grep -E "\/universe_[0-9]{10}.zip$" | sort | head -n -$BACKUP_VERSIONS | xargs -n1 rm -fv
    fi
else
    echo "💾 Backup disabled."
fi

# SteamCMD functions...
STEAMCMD_INSTALL() {
    echo "🚧 Installing SteamCMD..."
    mkdir -m 755 -p "${DIR_DATA_ROOT}/steam" || CONTAINER_ABORT "Unable to create ${DIR_DATA_ROOT}/steam"
    (
        cd "${DIR_DATA_ROOT}/steam" || exit 1
        echo "🚧 Installing SteamCMD..."
        rm -rf linux32 linux64 package public siteserverui steamcmd.sh
        curl -L -O "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" || exit 1
        tar zxvf "steamcmd_linux.tar.gz" || exit 1
        rm "steamcmd_linux.tar.gz"
        STEAMCMD_WARMUP "${1:-}"
    ) || CONTAINER_ABORT "Unable to install SteamCMD..."
}

STEAMCMD_WARMUP() {
    (
        cd "${DIR_DATA_ROOT}/steam" || exit 1
        echo "🚧 Warming up SteamCMD..."
        if [[ -f "linux64/steamcmd" ]]; then
            ${RUNNER}linux64/steamcmd +quit >> "$PATH_LOG"
        else
            if [[ -f "linux32/steamcmd" ]]; then
                ${RUNNER}linux32/steamcmd +quit >> "$PATH_LOG"
                ${RUNNER}linux64/steamcmd +quit >> "$PATH_LOG"
            else
                if [[ ! ${1:-} == "boop" ]]; then
                    STEAMCMD_INSTALL "boop"
                fi
            fi
        fi
    ) || CONTAINER_ABORT "Unable to warm up SteamCMD..."
}

STEAMCMD_RUN() {
    (
        cd "${DIR_DATA_ROOT}/steam" || exit 1
        if [[ -f "linux64/steamcmd" ]]; then
            ${RUNNER}linux64/steamcmd "$@" >> "$PATH_LOG"
        else
            echo "❌ SteamCMD is not installed..."
            exit 1
        fi
    )
}

# Update SteamCMD on launch if needed.
STEAM_SCRIPT_BASE="+@NoPromptForPassword 1 +@sSteamCmdForcePlatformType linux +@sSteamCmdForcePlatformBitness 64 +force_install_dir ${DIR_DATA_ROOT}/steam/"
if [[ ${UPDATE_STEAM,,} == true || ${UPDATE_GAME,,} == true || ${UPDATE_WORKSHOP,,} == true ]]; then
    STEAMCMD_WARMUP
else
    echo "🚧 SteamCMD update disabled."
fi

# Disabled these for now, most of the UPDATE_GAME_* parts need rework

# Update game data on launch if needed.
# if [[ ${UPDATE_GAME,,} == true ]]; then
#     echo "🎮 Game update enabled."
#     UPDATE_GAME_BIN=true
#     UPDATE_GAME_PAK_MAIN=true
#     UPDATE_GAME_PAK_OPENSB=true
# else
#     echo "🎮 Game update disabled."
#     if [[ ${LAUNCH_GAME,,} == true ]]; then
#         echo "🎮 Checking if game files exist..."
#         if [[ ${OPENSTARBOUND,,} == true ]]; then
#             if [[ -f "/server/starbound/linux/starbound_server" && $(stat -L --printf="%s" "/server/starbound/linux/starbound_server") -gt "40000000" ]]; then
#                 echo "✔️ starbound_server"
#                 [[ ${UPDATE_GAME,,} == true ]] && UPDATE_GAME_BIN=true || UPDATE_GAME_BIN=false
#             else
#                 echo "❌ starbound_server"
#                 UPDATE_GAME_BIN=true
#             fi
#             if [[ -f "/server/starbound/assets/opensb.pak" ]]; then
#                 echo "✔️ opensb.pak"
#                 [[ ${UPDATE_GAME,,} == true ]] && UPDATE_GAME_PAK_OPENSB=true || UPDATE_GAME_PAK_OPENSB=false
#             else
#                 echo "❌ opensb.pak"
#                 UPDATE_GAME_PAK_OPENSB=true
#             fi
#         else
#             UPDATE_GAME_PAK_OPENSB=false
#             if [[ -f "/server/starbound/linux/starbound_server" && $(stat -L --printf="%s" "/server/starbound/linux/starbound_server") -lt "40000000" ]]; then
#                 echo "✔️ starbound_server"
#                 [[ ${UPDATE_GAME,,} == true ]] && UPDATE_GAME_BIN=true || UPDATE_GAME_BIN=false
#             else
#                 echo "❌ starbound_server"
#                 UPDATE_GAME_BIN=true
#             fi
#         fi
#         if [[ -f "/server/starbound/assets/packed.pak" ]]; then
#             echo "✔️ packed.pak"
#             [[ ${UPDATE_GAME,,} == true ]] && UPDATE_GAME_PAK_MAIN=true || UPDATE_GAME_PAK_MAIN=false
#         else
#             echo "❌ packed.pak"
#             UPDATE_GAME_PAK_MAIN=true
#         fi
#     fi
# fi

# if [[ ${UPDATE_GAME_BIN,,} == true || ${UPDATE_GAME_PAK_MAIN,,} == true || ${UPDATE_GAME_PAK_OPENSB,,} == true ]]; then
#     echo "🎮 (Re)installing misssing parts..."
#     # Need anything from Steam? But skip this part during docker build.
#     if [[ ! ${DOCKER_BUILD,,} == true ]]; then
#         if [[ ${OPENSTARBOUND,,} == false && ${UPDATE_GAME_BIN,,} == true ]] || [[ ${UPDATE_GAME_PAK_MAIN,,} == true ]]; then
#             echo "🎮 Downloading files from Steam..."
#             # Here we only download the depots we need instead of the whole game, without specifying ManifestID Steam will download the latest available version. As a side effect this also prevents Steam from downloading unneeded runtimes.
#             # This is the Linux dedicated server program:
#             #   https://steamdb.info/depot/533833/
#             # And the packed.pak:
#             #   https://steamdb.info/depot/533831/
#             STEAMCMD_RUN $STEAM_SCRIPT_BASE +login $STEAM_LOGIN +download_depot 533830 533833 +download_depot 533830 533831 +quit
#             if [[ -d "/server/steamcmd/linux64/steamapps/content/app_533830/depot_533831/assets" && -d "/server/steamcmd/linux64/steamapps/content/app_533830/depot_533833/linux" ]]; then
#                 # Create the original directory struture so we don't have to modify sbinit.config.
#                 if [[ ${UPDATE_GAME_PAK_MAIN,,} == true ]]; then
#                     rm -fv "/server/starbound/assets/packed.pak"
#                     mv -fv "/server/steamcmd/linux64/steamapps/content/app_533830/depot_533831/assets/packed.pak" "/server/starbound/assets/packed.pak"
#                 fi
#                 if [[ ${OPENSTARBOUND,,} == false && ${UPDATE_GAME_BIN,,} == true ]]; then
#                     rm -rfv "/server/starbound/linux"
#                     mv -fv "/server/steamcmd/linux64/steamapps/content/app_533830/depot_533833/linux" "/server/starbound/linux"
#                 fi
#                 rm -rfv "/server/steamcmd/linux64/steamapps"
#             else
#                 CONTAINER_ABORT "Failed to download from Steam."
#             fi
#         fi
#     fi
#     # Need anything from OpenStarbound?
#     if [[ ${OPENSTARBOUND,,} == true && ${UPDATE_GAME_BIN,,} == true ]] || [[ ${UPDATE_GAME_PAK_OPENSB,,} == true ]]; then
#         echo "🎮 Copying OpenStarbond files from image..."
#         # Same as above, create the original directory struture.
#         if [[ ${UPDATE_GAME_PAK_OPENSB,,} == true ]]; then
#             cp -fv "/server/openstarbound/assets/opensb.pak" "/server/starbound/assets/opensb.pak"
#         fi
#         if [[ ${OPENSTARBOUND,,} == true && ${UPDATE_GAME_BIN,,} == true ]]; then
#             rm -rfv "/server/starbound/linux"
#             cp -rfv "/server/openstarbound/linux" "/server/starbound/linux"
#         fi
#     fi
# fi

if [[ ${UPDATE_WORKSHOP,,} == true ]]; then
    echo "⚙️ Workshop content update enabled."

    # Removes anything non-digit, keep numbers that are 9-10 digits, deduplication and sort, and output a json array.
    WORKSHOP_LIST_TO_ARRAY() {
        jq --null-input --arg LIST "$1" '[$LIST | scan("\\b[0-9]{9,10}\\b")] | unique'
    }

    # Convert the json array to comma list.
    WORKSHOP_ARRAY_TO_LIST() {
        jq --null-input --raw-output --argjson LIST "$1" '$LIST | join(",")'
    }

    # Convert the json array to Steam API POST body.
    WORKSHOP_ARRAY_TO_QUERY() {
        jq --null-input --raw-output --arg NAME "$1" --argjson IDS "$2" '"\($NAME)=\($IDS | length)&" + ($IDS | to_entries | map("publishedfileids[\(.key)]=\(.value)") | join("&"))'
    }

    WORKSHOP_ITEMS_JSON=$(WORKSHOP_LIST_TO_ARRAY "$WORKSHOP_ITEMS")
    WORKSHOP_ITEMS_COUNT=$(echo "$WORKSHOP_ITEMS_JSON" | jq 'length')
    echo "  📖 Items (${WORKSHOP_ITEMS_COUNT}): $(WORKSHOP_ARRAY_TO_LIST "$WORKSHOP_ITEMS_JSON")"

    WORKSHOP_COLLECTIONS_JSON=$(WORKSHOP_LIST_TO_ARRAY "$WORKSHOP_COLLECTIONS")
    WORKSHOP_COLLECTIONS_COUNT=$(echo "$WORKSHOP_COLLECTIONS_JSON" | jq 'length')
    echo "  📖 Collections (${WORKSHOP_COLLECTIONS_COUNT}): $(WORKSHOP_ARRAY_TO_LIST "$WORKSHOP_COLLECTIONS_JSON")"

    echo "  🔧 Combining all the ids..."
    if [[ $WORKSHOP_COLLECTIONS_COUNT -gt 0 ]]; then
        # https://steamapi.xpaw.me/ISteamRemoteStorage#GetCollectionDetails
        WORKSHOP_COLLECTIONS_EXPANDED=$(
            curl -fsS "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/" -d "$(WORKSHOP_ARRAY_TO_QUERY collectioncount "$WORKSHOP_COLLECTIONS_JSON")" |
            jq '[.response.collectiondetails[].children[]?.publishedfileid]'
        )
        if [[ -z "$WORKSHOP_COLLECTIONS_EXPANDED" ]]; then
            CONTAINER_ABORT "Steam API GetCollectionDetails failed."
        fi
    else
        WORKSHOP_COLLECTIONS_EXPANDED="[]"
    fi

    WORKSHOP_COMBINED_JSON=$(jq --null-input --argjson I "$WORKSHOP_ITEMS_JSON" --argjson C "$WORKSHOP_COLLECTIONS_EXPANDED" '$I + $C | unique')
    WORKSHOP_COMBINED_COUNT=$(echo "$WORKSHOP_COMBINED_JSON" | jq 'length')

    if [[ $WORKSHOP_COMBINED_COUNT -gt 0 ]]; then
        # https://steamapi.xpaw.me/ISteamRemoteStorage#GetPublishedFileDetails
        WORKSHOP_FINAL_JSON=$(
            curl -fsS "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" -d "$(WORKSHOP_ARRAY_TO_QUERY itemcount "$WORKSHOP_COMBINED_JSON")" |
            jq '[.response.publishedfiledetails[] | select(.consumer_app_id == 211820) | {title, publishedfileid, time_updated, file_size}]'
        )
        if [[ -z "$WORKSHOP_FINAL_JSON" ]]; then
            CONTAINER_ABORT "Steam API GetPublishedFileDetails failed."
        fi
    else
        WORKSHOP_FINAL_JSON="[]"
    fi

    WORKSHOP_FINAL_COUNT=$(echo "$WORKSHOP_FINAL_JSON" | jq 'length')
    echo "      📖 ${WORKSHOP_ITEMS_COUNT} item(s) + ${WORKSHOP_COLLECTIONS_COUNT} collection(s) -> ${WORKSHOP_COMBINED_COUNT} checked -> ${WORKSHOP_FINAL_COUNT} valid."

    echo "  🔧 Checking existing workshop content..."
    if [[ ! -f "${PATH_CONFIG_WS}" ]]; then
        echo "[]" > "${PATH_CONFIG_WS}"
    fi
    WORKSHOP_CURRENT_JSON=$(<"${PATH_CONFIG_WS}")
    WORKSHOP_CURRENT_IDS=$(echo "$WORKSHOP_CURRENT_JSON" | jq --raw-output '.[].publishedfileid')
    WORKSHOP_CURRENT_MISMATCH=()

    shopt -s nullglob
    for DIR in "${DIR_WORKSHOP_CONTENT}"/*/; do
        ID=${DIR%/}
        ID=${ID##*/}
        if ! echo "$WORKSHOP_CURRENT_IDS" | grep -Fxq -- "$ID"; then
            echo "      🗑️ ${ID}: Exists on disk but not in record."
            rm -rfv "${DIR}"
            continue
        fi
        RECORDED=$(echo "$WORKSHOP_CURRENT_JSON" | jq --arg ID "$ID" --raw-output '.[] | select(.publishedfileid == $ID) | .file_size // 0')
        SIZE=0
        for PAK in "${DIR}"*.pak; do
            ((SIZE += $(stat -c%s "${PAK}")))
        done
        if [[ "$SIZE" -ne "$RECORDED" ]]; then
            echo "      ⚠️ ${ID}: Size mismatch (disk ${SIZE}, record ${RECORDED})."
            rm -rfv "${DIR}"
            WORKSHOP_CURRENT_MISMATCH+=("${ID}")
        fi
    done
    shopt -u nullglob

    for ID in $WORKSHOP_CURRENT_IDS; do
        if [[ ! -d "${DIR_WORKSHOP_CONTENT}/${ID}" ]]; then
            echo "      ⚠️ ${ID}: Exists in record but not on disk (could be deleted by the size check)."
            WORKSHOP_CURRENT_MISMATCH+=("${ID}")
        fi
    done

    if [[ ${#WORKSHOP_CURRENT_MISMATCH[@]} -gt 0 ]]; then
        WORKSHOP_CURRENT_MISMATCH_JSON=$(WORKSHOP_LIST_TO_ARRAY "$(printf '%s,' "${WORKSHOP_CURRENT_MISMATCH[@]}")")
        WORKSHOP_CURRENT_JSON=$(jq --null-input --argjson C "$WORKSHOP_CURRENT_JSON" --argjson M "$WORKSHOP_CURRENT_MISMATCH_JSON" '$C | map(if (.publishedfileid as $ID | ($M | index($ID))) then .file_size = "0" else . end)')
    fi

    WORKSHOP_DELTA_JSON=$(jq --null-input --argjson F "$WORKSHOP_FINAL_JSON" --argjson C "$WORKSHOP_CURRENT_JSON" '
        [$F[].publishedfileid] as $FIDS |
        [$C[].publishedfileid] as $CIDS |
        {
            NEW:    [$F[] | select(.publishedfileid as $ID | ($CIDS | index($ID) | not))],
            DELETE: [$C[] | select(.publishedfileid as $ID | ($FIDS | index($ID) | not))],
            MODIFY: [$F[] | . as $f
                        | $C[] | select(.publishedfileid == $f.publishedfileid)
                        | select(.time_updated != $f.time_updated or .file_size != $f.file_size)
                        | $f]
        }')

    WORKSHOP_DELTA_NEW_COUNT=$(echo "$WORKSHOP_DELTA_JSON" | jq '.NEW | length')
    WORKSHOP_DELTA_DELETE_COUNT=$(echo "$WORKSHOP_DELTA_JSON" | jq '.DELETE | length')
    WORKSHOP_DELTA_MODIFY_COUNT=$(echo "$WORKSHOP_DELTA_JSON" | jq '.MODIFY | length')

    echo "      📖 Changes: ${WORKSHOP_DELTA_NEW_COUNT} new, ${WORKSHOP_DELTA_MODIFY_COUNT} updated, ${WORKSHOP_DELTA_DELETE_COUNT} removed."

    if [[ $WORKSHOP_DELTA_DELETE_COUNT -gt 0 ]]; then
        echo "  🔧 Removing ${WORKSHOP_DELTA_DELETE_COUNT} unlisted mod(s)..."
        for ID in $(echo "$WORKSHOP_DELTA_JSON" | jq --raw-output '.DELETE[].publishedfileid'); do
            echo "      🗑️ ${ID}"
            rm -rfv "${DIR_WORKSHOP_CONTENT}/${ID}"
        done
    fi

    if [[ $WORKSHOP_DELTA_NEW_COUNT -gt 0 || $WORKSHOP_DELTA_MODIFY_COUNT -gt 0 ]]; then
        WORKSHOP_ALL=$(echo "$WORKSHOP_DELTA_JSON" | jq --raw-output '.NEW+.MODIFY | [.[].publishedfileid] | join(",")')
        WORKSHOP_ALL_COUNT=$(echo $WORKSHOP_ALL, | tr -cd "," | wc -c)
        echo "  🔧 $WORKSHOP_ALL_COUNT item(s) to download."
        echo "    📖 $WORKSHOP_ALL"
        echo "  🔧 Currently installed workshop mods: "$(find ${DIR_WORKSHOP_CONTENT}/* -type d | wc -l)
        LOOP_COUNT=0
        LOOP_TMP_PREVIOUS_START=1
        LOOP_TMP_WORKSHOP_ID=""
        LOOP_TMP_WORKSHOP_ID_RETRY=""
        LOOP_TMP_WORKSHOP_SCRIPT=""
        LOOP_TMP_WORKSHOP_SCRIPT_RETRY=""
        if [[ $WORKSHOP_CHUNK == 0 ]]; then
            # A hacky way to turn it off, because we can't devide by zero.
            WORKSHOP_CHUNK=99999
        fi
        for LOOP_TMP_ITEM in ${WORKSHOP_ALL//,/ }; do
            ((LOOP_COUNT++))
            LOOP_TMP_WORKSHOP_ID+=$LOOP_TMP_ITEM,
            LOOP_TMP_WORKSHOP_SCRIPT+="+workshop_download_item 211820 $LOOP_TMP_ITEM validate "
            if [[ $(($LOOP_COUNT%$WORKSHOP_CHUNK)) == 0 || $LOOP_COUNT == $WORKSHOP_ALL_COUNT ]]; then
                LOOP_TMP_WORKSHOP_ID=${LOOP_TMP_WORKSHOP_ID%*,}
                echo "  🔧 Downloading mod $LOOP_TMP_PREVIOUS_START to $LOOP_COUNT"
                echo "    📖 $LOOP_TMP_WORKSHOP_ID"
                # This will loop 1+WORKSHOP_MAX_RETRY times.
                for ((LOOP_TEMP_WORKSHOP_RETRY = 0 ; LOOP_TEMP_WORKSHOP_RETRY <= WORKSHOP_MAX_RETRY ; LOOP_TEMP_WORKSHOP_RETRY++ )); do
                    rm -f "${HOME}/Steam/logs/workshop_log.txt"
                    STEAMCMD_RUN $STEAM_SCRIPT_BASE +login anonymous $LOOP_TMP_WORKSHOP_SCRIPT +quit
                    # Check if this group is downloaded successfully, mark down the unsuccessful ones.
                    LOOP_TEMP_WORKSHOP_SUCCESS=1
                    for LOOP_TMP_WORKSHOP_ID_ITEM in ${LOOP_TMP_WORKSHOP_ID//,/ }; do
                        if grep -swq "Download item $LOOP_TMP_WORKSHOP_ID_ITEM result \: OK" "${HOME}/Steam/logs/workshop_log.txt"; then
                            LOOP_TEMP_WORKSHOP_SUCCESS=$(($LOOP_TEMP_WORKSHOP_SUCCESS & 1))
                            echo "    ✔️ $LOOP_TMP_WORKSHOP_ID_ITEM"
                        else
                            LOOP_TEMP_WORKSHOP_SUCCESS=$(($LOOP_TEMP_WORKSHOP_SUCCESS & 0))
                            echo "    ❌ $LOOP_TMP_WORKSHOP_ID_ITEM"
                            LOOP_TMP_WORKSHOP_ID_RETRY+=$LOOP_TMP_WORKSHOP_ID_ITEM","
                            LOOP_TMP_WORKSHOP_SCRIPT_RETRY+="+workshop_download_item 211820 $LOOP_TMP_WORKSHOP_ID_ITEM validate "
                        fi
                    done
                    # All success       -> Break the loop
                    # Retries available -> Replace the group list with unsuccessful mods, wait 30s and retry
                    # Retries exhausted -> Exit container
                    if [[ $LOOP_TEMP_WORKSHOP_SUCCESS == 0 ]]; then
                        if [[ $LOOP_TEMP_WORKSHOP_RETRY == $WORKSHOP_MAX_RETRY ]]; then
                            CONTAINER_ABORT "Failed to download workshop mods after ${WORKSHOP_MAX_RETRY} retries."
                        else
                            echo "  ❌ Download failed, retry $(($LOOP_TEMP_WORKSHOP_RETRY+1))/$WORKSHOP_MAX_RETRY in 30 seconds."
                            LOOP_TMP_WORKSHOP_ID=${LOOP_TMP_WORKSHOP_ID_RETRY%*,}
                            LOOP_TMP_WORKSHOP_SCRIPT=$LOOP_TMP_WORKSHOP_SCRIPT_RETRY
                            LOOP_TMP_WORKSHOP_ID_RETRY=""
                            LOOP_TMP_WORKSHOP_SCRIPT_RETRY=""
                            sleep 30
                        fi
                    else
                        break
                    fi
                done
                LOOP_TMP_WORKSHOP_ID=""
                LOOP_TMP_WORKSHOP_SCRIPT=""
                LOOP_TMP_PREVIOUS_START=$(($LOOP_COUNT+1))
            fi
        done
    else
        echo "  🔧 Nothing to install."
    fi

    echo "$WORKSHOP_FINAL_JSON" > "${PATH_CONFIG_WS}"
else
    echo "⚙️ Workshop content update disabled."
fi

} > >(tee -a "$PATH_LOG") 2>&1

if [[ ${LAUNCH_GAME,,} == true ]]; then
    {
    # if [[ ${OPENSTARBOUND,,} == false && -f "/server/starbound/assets/opensb.pak" ]]; then
    #     echo "  🔧 Running Steam version but opensb.pak exists."
    #     rm -fv "/server/starbound/assets/opensb.pak"
    # fi
    echo "  🔧 Removing old symlinks..."
    find ${DIR_DATA_ROOT}/mods/workshop-* -xtype l -delete
    if [[ -d "${DIR_WORKSHOP_CONTENT}" ]]; then
        echo "  🔧 Recreating workshop symlinks..."
        # Extract parts from .pak path
        # /server/starbound/steamapps/workshop/content/211820/123456789/foobar.pak
        #                  (\1                                                   )
        #                                                     (\2     ) (\3      )
        # Create Relative source path
        # ../steamapps/workshop/content/211820/123456789/foobar.pak
        #   (\1                                                   )
        # Create Symlink
        # /server/starbound/mods/workshop-123456789-foobar.pak
        #                                 (\2     ) (\3      )
        find /server/starbound/steamapps/workshop/content/211820/ -type f -name "*.pak" | sed -r "s/^\/server\/starbound(.*211820\/([0-9]+)\/(.*))$/\"\.\.\1\" \"\/server\/starbound\/mods\/workshop\-\2\-\3\"/" | xargs -n2 ln -vfs
    fi
    echo "🎮 Launching Starbound..."
    cd "/server/starbound/linux"
    } > >(tee -a "$PATH_LOG") 2>&1
    if [[ ${OPENSTARBOUND,,} == true ]]; then
        exec ./starbound_server
    else
        exec ${RUNNER}starbound_server
    fi
else
    echo "👋 Adios"
    # Uncomment to keep the container alive for debugging
    #sleep infinity
fi
