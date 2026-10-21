#!/bin/bash

STEAMCMD_INSTALL() {
    mkdir -p /server/steamcmd
    pushd /server/steamcmd > /dev/null
    if [[ $(realpath .) == "/server/steamcmd" ]]; then
        echolog "🚧 Installing SteamCMD..."
        rm -rf linux32 linux64 package public siteserverui steamcmd.sh
        curl -L -O "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
        tar zxvf "steamcmd_linux.tar.gz"
        rm "steamcmd_linux.tar.gz"
        STEAMCMD_WARMUP "${1:-}"
    else
        echolog "❌ Unable to install SteamCMD..."
    fi
    popd > /dev/null
}

STEAMCMD_WARMUP() {
    pushd /server/steamcmd > /dev/null
    echolog "🚧 Warming up SteamCMD..."
    if [[ -f "linux64/steamcmd" ]]; then
        ${RUNNER}linux64/steamcmd +quit >> $CONTAINER_LOGFILE
    else
        if [[ -f "linux32/steamcmd" ]]; then
            ${RUNNER}linux32/steamcmd +quit >> $CONTAINER_LOGFILE
            ${RUNNER}linux64/steamcmd +quit >> $CONTAINER_LOGFILE
        else
            if [[ ! ${1:-} == "boop" ]]; then
                STEAMCMD_INSTALL "boop"
            fi
        fi
    fi
    popd > /dev/null
}

STEAMCMD_RUN() {
    pushd /server/steamcmd > /dev/null
    if [[ -f "linux64/steamcmd" ]]; then
        ${RUNNER}linux64/steamcmd "$@" >> $CONTAINER_LOGFILE
    else
        # Maybe I'll make it auto install in the future, but the current version is more of a "make it modular whilst fixing important stuff", I'll deal with it later
        echolog "❌ SteamCMD is not installed..."
    fi
    popd > /dev/null
}