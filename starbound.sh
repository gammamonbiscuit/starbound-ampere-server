#!/bin/bash
echo "🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫"
echo "   Biscuit's Starbound ARM server docker   "
echo "🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫🍫"

if [[ ! -f "/server/starbound.env" ]]; then
    echo "🚧 Creating config file..."
    tee "/server/starbound.env" <<EOF >/dev/null
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

# Decides whether to update all game files or not, if LAUNCH_GAME is set to true and the game is incomplete, this script will still re-download the missing parts.
# Default: false
UPDATE_GAME=$UPDATE_GAME

# Decides whether to update workshop mods or not, whilst skipping already installed mods.
# Default: false
UPDATE_WORKSHOP=$UPDATE_WORKSHOP

# Changes UPDATE_WORKSHOP behaviour to verify and download every workshop mods if needed.
# Default: false
UPDATE_WORKSHOP_FORCE=$UPDATE_WORKSHOP_FORCE

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

# Delete workshop mods that are no longer included in WORKSHOP_ITEMS or WORKSHOP_COLLECTIONS.
# Default: true
WORKSHOP_PRUNE=$WORKSHOP_PRUNE

# Number of retries should be performed when there are errors downloading mods, container will exit after all retries are exhausted.
# Default: 3
WORKSHOP_MAX_RETRY=$WORKSHOP_MAX_RETRY

EOF
else
    echo "🚧 Reading config file..."
    source "/server/starbound.env"
fi

if [[ $OPENSTARBOUND == true ]]; then
    echo "🎮 OpenStarbound selected."
    echo "🎮 https://github.com/OpenStarbound/OpenStarbound"
else
    echo "🎮 Official Steam verison selected."
    echo "🎮 https://store.steampowered.com/app/211820/Starbound/"
fi

STEAM_SCRIPT_BASE="+@NoPromptForPassword 1 +@sSteamCmdForcePlatformType linux +@sSteamCmdForcePlatformBitness 64 +force_install_dir /server/starbound/"
mkdir -m 755 -p /server/{steamcmd/home,starbound/{assets,mods,storage,logs,steamapps}}

# Update SteamCMD on every launch.
pushd /server/steamcmd > /dev/null
if [[ ! -f "linux32/steamcmd" ]]; then
    # Should already exists in the image, just in case the user mounts the steamcmd directory to host.
    echo "🚧 SteamCMD not found, reinstalling..."
    curl -L -O "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    tar zxvf "steamcmd_linux.tar.gz"
    rm "steamcmd_linux.tar.gz"
    # For some reason it needs to update twice?
    box64 linux32/steamcmd $STEAM_SCRIPT_BASE +quit >/dev/null
else
    echo "🚧 Updating SteamCMD..."
fi
box64 linux32/steamcmd $STEAM_SCRIPT_BASE +quit >/dev/null
find "package" -name "*.zip.*" -delete
popd > /dev/null

if [[ $UPDATE_GAME == true ]]; then
    echo "🎮 Game update enabled."
    UPDATE_GAME_BIN=true
    UPDATE_GAME_PAK_MAIN=true
    UPDATE_GAME_PAK_OPENSB=true
else
    echo "🎮 Game update disabled."
    if [[ $LAUNCH_GAME == true ]]; then
        echo "🎮 Checking if game files exist..."
        if [[ $OPENSTARBOUND == true ]]; then
            if [[ -f "/server/starbound/linux/starbound_server" && $(stat -L --printf="%s" "/server/starbound/linux/starbound_server") -gt "40000000" ]]; then
                echo "✔️ starbound_server"
                [[ $UPDATE_GAME = true ]] && UPDATE_GAME_BIN=true || UPDATE_GAME_BIN=false
            else
                echo "❌ starbound_server"
                UPDATE_GAME_BIN=true
            fi
            if [[ -f "/server/starbound/assets/opensb.pak" ]]; then
                echo "✔️ opensb.pak"
                [[ $UPDATE_GAME == true ]] && UPDATE_GAME_PAK_OPENSB=true || UPDATE_GAME_PAK_OPENSB=false
            else
                echo "❌ opensb.pak"
                UPDATE_GAME_PAK_OPENSB=true
            fi
        else
            UPDATE_GAME_PAK_OPENSB=false
            if [[ -f "/server/starbound/linux/starbound_server" && $(stat -L --printf="%s" "/server/starbound/linux/starbound_server") -lt "40000000" ]]; then
                echo "✔️ starbound_server"
                [[ $UPDATE_GAME == true ]] && UPDATE_GAME_BIN=true || UPDATE_GAME_BIN=false
            else
                echo "❌ starbound_server"
                UPDATE_GAME_BIN=true
            fi
        fi
        if [[ -f "/server/starbound/assets/packed.pak" ]]; then
            echo "✔️ packed.pak"
            [[ $UPDATE_GAME == true ]] && UPDATE_GAME_PAK_MAIN=true || UPDATE_GAME_PAK_MAIN=false
        else
            echo "❌ packed.pak"
            UPDATE_GAME_PAK_MAIN=true
        fi
    fi
fi

if [[ $UPDATE_GAME_BIN == true || $UPDATE_GAME_PAK_MAIN == true || $UPDATE_GAME_PAK_OPENSB == true ]]; then
    echo "🎮 (Re)installing misssing parts..."
    # Need anything from Steam? But skip this part during docker build.
    if [[ ! $DOCKER_BUILD == true ]]; then
        if [[ $OPENSTARBOUND == false && $UPDATE_GAME_BIN == true ]] || [[ $UPDATE_GAME_PAK_MAIN == true ]]; then
            echo "🎮 Downloading files from Steam..."
            # Here we only download the depots we need instead of the whole game, without specifying ManifestID Steam will download the latest available version. As a side effect this also prevents Steam from downloading unneeded runtimes.
            # This is the Linux dedicated server program:
            #   https://steamdb.info/depot/533833/
            # And the packed.pak:
            #   https://steamdb.info/depot/533831/
            box64 /server/steamcmd/linux32/steamcmd $STEAM_SCRIPT_BASE +login $STEAM_LOGIN +download_depot 533830 533833 +download_depot 533830 533831 +quit
            if [[ -d "/server/steamcmd/linux32/steamapps/content/app_533830/depot_533831/assets" && -d "/server/steamcmd/linux32/steamapps/content/app_533830/depot_533833/linux" ]]; then
                # Create the original directory struture so we don't have to modify sbinit.config.
                if [[ $UPDATE_GAME_PAK_MAIN == true ]]; then
                    rm -fv "/server/starbound/assets/packed.pak"
                    mv -f "/server/steamcmd/linux32/steamapps/content/app_533830/depot_533831/assets/packed.pak" "/server/starbound/assets/packed.pak"
                fi
                if [[ $OPENSTARBOUND == false && $UPDATE_GAME_BIN == true ]]; then
                    rm -rfv "/server/starbound/linux"
                    mv -f "/server/steamcmd/linux32/steamapps/content/app_533830/depot_533833/linux" "/server/starbound/linux"
                fi
                rm -rfv "/server/steamcmd/linux32/steamapps"
            else
                echo "❌ Failed to download from Steam, abort."
                exit 1
            fi
        fi
    fi
    # Need anything from OpenStarbound?
    if [[ $OPENSTARBOUND == true && $UPDATE_GAME_BIN == true ]] || [[ $UPDATE_GAME_PAK_OPENSB == true ]]; then
        echo "🎮 Copying OpenStarbond files from image..."
        # Same as above, create the original directory struture.
        if [[ $UPDATE_GAME_PAK_OPENSB == true ]]; then
            cp -fv "/server/openstarbound/assets/opensb.pak" "/server/starbound/assets/opensb.pak"
        fi
        if [[ $OPENSTARBOUND == true && $UPDATE_GAME_BIN == true ]]; then
            rm -rfv "/server/starbound/linux"
            cp -rfv "/server/openstarbound/linux" "/server/starbound/linux"
        fi
    fi
fi

# Finish docker build
if [[ $DOCKER_BUILD == true ]]; then
    exit
fi

if [[ $UPDATE_WORKSHOP == true ]]; then
    echo "⚙️ Workshop content update enabled."
    WORKSHOP_ALL=""
    WORKSHOP_ALL_COUNT=0
    # Removes anything non-digit, deduplication and sort, and output a comma-separated list.
    WORKSHOP_ITEMS_SANITISED=$(echo "["$(echo $WORKSHOP_ITEMS | sed -re "s/[^0-9]+/,/g;s/\,$//;s/^,//")"]" | jq "unique|join(\",\")" | sed "s/\"//g")
    WORKSHOP_COLLECTIONS_SANITISED=$(echo "["$(echo $WORKSHOP_COLLECTIONS | sed -re "s/[^0-9]+/,/g;s/\,$//;s/^,//")"]" | jq "unique|join(\",\")" | sed "s/\"//g")
    if [[ -n "$WORKSHOP_ITEMS_SANITISED" ]]; then
        WORKSHOP_ITEMS_COUNT=$(echo $WORKSHOP_ITEMS_SANITISED, | tr -cd "," | wc -c)
        echo "  🔧 $WORKSHOP_ITEMS_COUNT individual item(s)"
        echo "    📖 $WORKSHOP_ITEMS_SANITISED"
    else
        echo "  🔧 No individual workshop item specified."
    fi
    if [[ -n "$WORKSHOP_COLLECTIONS_SANITISED" ]]; then
        WORKSHOP_COLLECTIONS_COUNT=$(echo $WORKSHOP_COLLECTIONS_SANITISED, | tr -cd "," | wc -c)
        echo "  🔧 $WORKSHOP_COLLECTIONS_COUNT collection(s)"
        echo "    📖 $WORKSHOP_COLLECTIONS_SANITISED"
        # Document:
        # https://steamapi.xpaw.me/#ISteamRemoteStorage/GetCollectionDetails
        # For querying a list N with n ids, send the following POST request to Steam API:
        # https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/
        #        ?collectioncount=n
        #        &publishedfileids[0]=N1
        #        &publishedfileids[1]=N2
        #        ...
        #        &publishedfileids[n-1]=Nn
        WORKSHOP_COLLECTIONS_QUERY="collectioncount=$WORKSHOP_COLLECTIONS_COUNT"
        for COLLECTION in ${WORKSHOP_COLLECTIONS_SANITISED//,/ }; do
            ((WORKSHOP_COLLECTIONS_COUNT--))
            WORKSHOP_COLLECTIONS_QUERY+="&publishedfileids%5B$WORKSHOP_COLLECTIONS_COUNT%5D=$COLLECTION"
        done
        echo "    ☁️ Calling Steam API to get collection data..."
        WORKSHOP_COLLECTIONS_EXPANDED=$(curl -s "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/" -d $WORKSHOP_COLLECTIONS_QUERY)
        if jq -e . >/dev/null 2>&1 <<<$WORKSHOP_COLLECTIONS_EXPANDED; then
            WORKSHOP_COLLECTIONS_EXPANDED=$(echo $WORKSHOP_COLLECTIONS_EXPANDED | jq "[.response.collectiondetails.[].children|select(.!=null).[].publishedfileid|tonumber]|unique|join(\",\")" | sed "s/\"//g")
            if [[ -n "$WORKSHOP_COLLECTIONS_EXPANDED" ]]; then
                WORKSHOP_COLLECTIONS_EXPANDED_COUNT=$(echo $WORKSHOP_COLLECTIONS_EXPANDED, | tr -cd , | wc -c)
                echo "    ☁️ $WORKSHOP_COLLECTIONS_EXPANDED_COUNT individual item(s)"
                echo "      📖 $WORKSHOP_COLLECTIONS_EXPANDED"
            else
                echo "    ❌ Failed to retrive data, abort."
                exit 1
            fi
        else
            echo "    ❌ Failed to retrive data, abort."
            exit 1
        fi
    else
        echo "  🔧 No workshop collection specified."
    fi

    if [[ $UPDATE_WORKSHOP_FORCE == true ]]; then
        echo "  🔧 Combining all the ids..."
        WORKSHOP_ALL_ORIGINAL=$(echo "[[$WORKSHOP_ITEMS_SANITISED],[$WORKSHOP_COLLECTIONS_EXPANDED]]" | jq ".|flatten|unique|join(\",\")" | sed "s/\"//g")
        WORKSHOP_ALL=$WORKSHOP_ALL_ORIGINAL
    else
        echo "  🔧 Combining all the ids (skip existing mods)..."
        WORKSHOP_ALL_ORIGINAL=$(echo "[[$WORKSHOP_ITEMS_SANITISED],[$WORKSHOP_COLLECTIONS_EXPANDED]]" | jq ".|flatten|unique|join(\",\")" | sed "s/\"//g")
        for LOOP_TMP_ITEM in ${WORKSHOP_ALL_ORIGINAL//,/ }; do
            if [[ ! -d "/server/starbound/steamapps/workshop/content/211820/$LOOP_TMP_ITEM" ]]; then
                WORKSHOP_ALL+=$LOOP_TMP_ITEM,
            fi
        done
        WORKSHOP_ALL=${WORKSHOP_ALL%*,}
    fi

    if [[ -n "$WORKSHOP_ALL" ]]; then
        WORKSHOP_ALL_COUNT=$(echo $WORKSHOP_ALL, | tr -cd "," | wc -c)
        echo "  🔧 $WORKSHOP_ALL_COUNT individual item(s)"
        echo "    📖 $WORKSHOP_ALL"
        echo "  🔧 Currently installed workshop mods: "$(find /server/starbound/steamapps/workshop/content/211820/* -type d | wc -l)
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
                LOOP_TEMP_WORKSHOP_SUCCESS=1
                echo "  🔧 Downloading mod $LOOP_TMP_PREVIOUS_START to $LOOP_COUNT"
                echo "    📖 $LOOP_TMP_WORKSHOP_ID"
                # This will loop 1+WORKSHOP_MAX_RETRY times.
                for ((LOOP_TEMP_WORKSHOP_RETRY = 0 ; LOOP_TEMP_WORKSHOP_RETRY <= WORKSHOP_MAX_RETRY ; LOOP_TEMP_WORKSHOP_RETRY++ )); do
                    rm -f "/server/steamcmd/home/Steam/logs/workshop_log.txt"
                    box64 /server/steamcmd/linux32/steamcmd $STEAM_SCRIPT_BASE +login anonymous $LOOP_TMP_WORKSHOP_SCRIPT +quit >/dev/null
                    # Sometimes SteamCMD can't even launch normally, if that's the case don't bother checking every mods and finish this loop right here.
                    if [[ ! -f "/server/steamcmd/home/Steam/logs/workshop_log.txt" ]]; then
                        echo "  ❌ Unable to download anything, retry $(($LOOP_TEMP_WORKSHOP_RETRY+1))/$WORKSHOP_MAX_RETRY in 30 seconds."
                        sleep 30
                        continue
                    fi
                    # Check if this group is downloaded successfully, mark down the unsuccessful ones.
                    for LOOP_TMP_WORKSHOP_ID_ITEM in ${LOOP_TMP_WORKSHOP_ID//,/ }; do
                        if grep -swq "Download item $LOOP_TMP_WORKSHOP_ID_ITEM result \: OK" "/server/steamcmd/home/Steam/logs/workshop_log.txt"; then
                            LOOP_TEMP_WORKSHOP_SUCCESS=$(($LOOP_TEMP_WORKSHOP_SUCCESS & 1))
                            echo "    ✔️ $LOOP_TMP_WORKSHOP_ID_ITEM"
                        else
                            LOOP_TEMP_WORKSHOP_SUCCESS=$(($LOOP_TEMP_WORKSHOP_SUCCESS & 0))
                            echo "    ❌ $LOOP_TMP_WORKSHOP_ID_ITEM"
                            LOOP_TMP_WORKSHOP_ID_RETRY+=$LOOP_TMP_WORKSHOP_ID_ITEM","
                            LOOP_TMP_WORKSHOP_SCRIPT_RETRY+="+workshop_download_item 211820 $LOOP_TMP_ITEM validate "
                        fi
                    done
                    # All success       -> Break the loop
                    # Retries available -> Replace the group list with unsuccessful mods, wait 30s and retry
                    # Retries exhausted -> Exit container
                    if [[ $LOOP_TEMP_WORKSHOP_SUCCESS == 0 ]]; then
                        if [[ $LOOP_TEMP_WORKSHOP_RETRY == $WORKSHOP_MAX_RETRY ]]; then
                            echo "  ❌ Failed to download data, abort."
                            exit 1
                        else
                            echo "  ❌ Download failed, retry $(($LOOP_TEMP_WORKSHOP_RETRY+1))/$WORKSHOP_MAX_RETRY in 30 seconds."
                            LOOP_TMP_WORKSHOP_ID=${LOOP_TMP_WORKSHOP_ID_RETRY%*,}
                            LOOP_TMP_WORKSHOP_SCRIPT=LOOP_TMP_WORKSHOP_SCRIPT_RETRY
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

    if [[ $WORKSHOP_PRUNE == true ]]; then
        echo "  🔧 Deleting old mods..."
        # Will fail if it is already empty, but this is not a breaking error so I just keep it as is.
        find /server/starbound/steamapps/workshop/content/211820/* -type d | grep -v -E $(echo $WORKSHOP_ALL_ORIGINAL | sed "s/,/\|/g") | xargs -n1 rm -rfv
    else
        echo "  🔧 Prune disabled."
    fi
else
    echo "⚙️ Workshop content update disabled."
fi

if [[ $LAUNCH_GAME == true ]]; then
    if [[ $OPENSTARBOUND == false && -f "/server/starbound/assets/opensb.pak" ]]; then
        echo "  🔧 Running Steam version but opensb.pak exists."
        rm -fv "/server/starbound/assets/opensb.pak"
    fi
    if [[ -d "/server/starbound/steamapps/workshop/content/211820" ]]; then
        echo "  🔧 Recreating workshop symlinks..."
        rm -rfv /server/starbound/mods/workshop-*
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
    if [[ $OPENSTARBOUND == true ]]; then
        ./starbound_server
    else
        box64 starbound_server
    fi
fi

# Uncomment to keep the container alive for debugging
echo "👋 Adios"
#sleep infinity
