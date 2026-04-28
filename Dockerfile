FROM scratch AS init

ARG TARGETPLATFORM \
    DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/compile/vcpkg

ENV OPENSTARBOUND_VERSION= \
    OPENSTARBOUND=true \
    STEAM_LOGIN="anonymous" \
    LAUNCH_GAME=true \
    BACKUP_ENABLED=true \
    BACKUP_VERSIONS=10 \
    BACKUP_COOLDOWN=1800 \
    BACKUP_MODS_MANUAL=false \
    BACKUP_MODS_WORKSHOP=false \
    UPDATE_STEAM=false \
    UPDATE_GAME=false \
    UPDATE_WORKSHOP=false \
    UPDATE_WORKSHOP_FORCE=false \
    WORKSHOP_ITEMS="" \
    WORKSHOP_COLLECTIONS="" \
    WORKSHOP_CHUNK=20 \
    WORKSHOP_PRUNE=true \
    WORKSHOP_MAX_RETRY=3 \
    FEX_ENABLED=false \
    BOX64_LOG=0 \
    BOX64_NOBANNER=1 \
    BOX64_DYNAREC_STRONGMEM=1 \
    BOX64_DYNAREC_BIGBLOCK=1 \
    BOX64_DYNAREC_SAFEFLAGS=1 \
    BOX64_DYNAREC_FASTROUND=1 \
    BOX64_DYNAREC_FASTNAN=1 \
    BOX64_DYNAREC_X87DOUBLE=0 \
    TARGETPLATFORM=${TARGETPLATFORM}

SHELL ["/bin/bash", "-c"]

FROM init AS base

COPY --from=debian:trixie-slim / /

RUN --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/debconf \
    apt update && \
    apt install -y --no-install-recommends curl ca-certificates zip unzip tar git jq squashfs-tools $([[ "$TARGETPLATFORM" == "linux/amd64" ]] && echo "lib32stdc++6")

FROM base AS builder

RUN --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/debconf \
    if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        apt install -y build-essential cmake pkg-config libxmu-dev libxi-dev libgl-dev libglu1-mesa-dev libsdl2-dev python3-jinja2 ninja-build autoconf automake autoconf-archive libltdl-dev qemu-user-static; \
    fi

RUN mkdir -p /{compile,output/{steamcmd,box64,openstarbound}}

WORKDIR /compile

FROM builder AS builder-steam

RUN if [[ "$TARGETPLATFORM" == "$TARGETPLATFORM" ]]; then \
        cd /output/steamcmd && \
        curl -L -O "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" && \
        tar zxvf "steamcmd_linux.tar.gz" && \
        rm "steamcmd_linux.tar.gz"; \
    fi

FROM init AS builder-fex

COPY --from=debian:bookworm-slim / /

RUN mkdir -p /{compile,output/fex}

WORKDIR /compile

RUN --mount=type=cache,id=apt-bookworm-$TARGETPLATFORM,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=apt-bookworm-$TARGETPLATFORM,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,id=apt-bookworm-$TARGETPLATFORM,sharing=locked,target=/var/cache/debconf \
    if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        apt update && \
        apt install -y git cmake lld clang llvm ninja-build pkg-config libsdl2-dev qtbase5-dev qtdeclarative5-dev && \
        git clone --depth 1 --recurse-submodules https://github.com/FEX-Emu/FEX.git && \
        cd /compile/FEX && \
        mkdir build && \
        CC=clang CXX=clang++ cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True -DBUILD_TESTING=False -DENABLE_ASSERTIONS=False -G Ninja . && \
        ninja -j$(nproc) && \
        mv /compile/FEX/Bin/* /output/fex; \
    fi

FROM --platform=linux/amd64 debian:trixie-slim AS rootfs
FROM builder AS builder-fex-rootfs

COPY --from=rootfs / /output/rootfs

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        cd /output/rootfs && \
        chroot . apt update && \
        chroot . apt install -y lib32gcc-s1 && \
        rm -rf boot dev home media mnt proc root srv tmp sys opt var/cache/apt var/lib/apt var/lib/dpkg && \
        cd etc && \
        rm -f hosts resolv.conf timezone localtime passwd; \
    else \
        rm -rf /output/rootfs && \
        mkdir /output/rootfs; \
    fi

FROM builder AS builder-box64

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        git clone --depth 1 https://github.com/ptitSeb/box64.git && \
        cd /compile/box64 && \
        cmake . -D ADLINK=1 -D ARM_DYNAREC=ON -D BOX32=ON -D BOX32_BINFMT=ON -D CMAKE_BUILD_TYPE=Release && \
        make -j$(nproc) && \
        make install DESTDIR=/output/box64; \
    fi

FROM builder AS builder-osb

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        if [[ -z "$OPENSTARBOUND_VERSION" ]]; then \
            ASSETS=https://nightly.link/OpenStarbound/OpenStarbound/workflows/build/main; \
        else \
            ASSETS=https://github.com/OpenStarbound/OpenStarbound/releases/download/${OPENSTARBOUND_VERSION}; \
        fi && \
        curl -L -O "${ASSETS}/OpenStarbound-Linux-ARM-Clang-{Server,Client}.zip" && \
        if [[ $(head -c 2 OpenStarbound-Linux-ARM-Clang-Server.zip) == "PK" && $(head -c 2 OpenStarbound-Linux-ARM-Clang-Client.zip) == "PK" ]]; then \
            unzip "OpenStarbound-Linux-ARM-Clang-*.zip" && \
            if [[ -f "server.tar" && -f "client.tar" ]]; then \
                tar xvf "server.tar" && \
                tar xvf "client.tar" && \
                mv server_distribution/* /output/openstarbound/ && \
                mv client_distribution/linux/asset_packer client_distribution/linux/asset_unpacker /output/openstarbound/linux/ && \
                rm /output/openstarbound/mods/mods_go_here; \
            else \
                exit 1; \
            fi; \
        fi; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" && ! $(compgen -G "/output/openstarbound/linux/starbound_server") ]]; then \
        git clone --depth 1 https://github.com/microsoft/vcpkg.git && \
        cd /compile/vcpkg && \
        ./bootstrap-vcpkg.sh -disableMetrics; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" && ! $(compgen -G "/output/openstarbound/linux/starbound_server") ]]; then \
        git clone --depth 1 --branch ${OPENSTARBOUND_VERSION:-main} https://github.com/OpenStarbound/OpenStarbound.git && \
        if [[ $(compgen -G "/compile/OpenStarbound/triplets/arm64-linux-mixed*") ]]; then \
            cd /compile/OpenStarbound/source; \
        else \
            cd /compile/OpenStarbound/cmake && \
            sed -i -r 's/(\#elif\sdefined\(__arm64__\))/\1 || defined(__aarch64__)/' TargetArch.cmake && \
            cd /compile/OpenStarbound/triplets && \
            cat x64-linux-mixed.cmake | sed -r '/\"\-DOPUS\_X86.*?\"/d;/discord/,/endif/d;s/ARCHITECTURE\sx64/ARCHITECTURE arm64/;s/(VCPKG_CMAKE_CONFIGURE_OPTIONS)/\1\n    \"-DOPUS_ARM_MAY_HAVE_NEON=ON\"\n    \"-DOPUS_ARM_MAY_HAVE_NEON_INTR=ON\"/' >./arm64-linux-mixed.cmake && \
            cat arm64-linux-mixed.cmake | sed -r 's/(set\(VCPKG_CMAKE_SYSTEM_NAME Linux\))/\1\nset(VCPKG_CHAINLOAD_TOOLCHAIN_FILE ${CMAKE_CURRENT_LIST_DIR}\/..\/toolchains\/linux-clang.cmake)/' >arm64-linux-mixed-clang.cmake && \
            cd /compile/OpenStarbound/source && \
            cat CMakePresets.json | jq '. + {"testPresets": .testPresets | walk( if type == "string" then sub("linux";"linux-arm") else . end )} + {"buildPresets": .buildPresets | walk( if type == "string" then sub("linux";"linux-arm") else . end )} + {"configurePresets": .configurePresets | walk( if type == "string" then sub("(?<x>(^|[^-]))linux(?<y>[^\/])";"\(.x)linux-arm\(.y)") | sub("x64";"arm64") | sub("RelWithDebInfo";"Release") else . end ) } | del(.configurePresets.[], .buildPresets.[], .testPresets.[] | select(.hidden != true) | select(.name | startswith("linux") | not )) | .configurePresets.[].cacheVariables.STAR_ENABLE_STEAM_INTEGRATION = false | .configurePresets.[].cacheVariables.STAR_ENABLE_DISCORD_INTEGRATION = false' >CMakePresets.json.tmp && \
            mv -f CMakePresets.json.tmp CMakePresets.json; \
        fi && \
        cmake --preset=linux-arm-release; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" && ! $(compgen -G "/output/openstarbound/linux/starbound_server") ]]; then \
        cd /compile/OpenStarbound/build/linux-arm-release && \
        cmake --build . --parallel $(nproc) && \
        cd /compile/OpenStarbound && \
        mkdir -p /output/openstarbound/{assets,mods,linux} && \
        ./dist/asset_packer -c scripts/packing.config -s assets/opensb /output/openstarbound/assets/opensb.pak && \
        mv \
          dist/starbound_server \
          dist/btree_repacker \
          dist/asset_packer \
          dist/asset_unpacker \
          scripts/ci/linux/sbinit.config \
          scripts/steam_appid.txt \
          /output/openstarbound/linux/; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then \
        if [[ -z "$OPENSTARBOUND_VERSION" ]]; then \
            ASSETS=https://nightly.link/OpenStarbound/OpenStarbound/workflows/build/main; \
        else \
            ASSETS=https://github.com/OpenStarbound/OpenStarbound/releases/download/${OPENSTARBOUND_VERSION}; \
        fi && \
        curl -L -O "${ASSETS}/OpenStarbound-Linux-Clang-{Server,Client}.zip" && \
        unzip "OpenStarbound-Linux-Clang-*.zip" && \
        if [[ -f "server.tar" && -f "client.tar" ]]; then \
            tar xvf "server.tar" && \
            tar xvf "client.tar" && \
            mv server_distribution/* /output/openstarbound/ && \
            mv client_distribution/linux/asset_packer client_distribution/linux/asset_unpacker /output/openstarbound/linux/ && \
            rm /output/openstarbound/mods/mods_go_here; \
        else \
            exit 1; \
        fi \
    fi

FROM base AS final

RUN mkdir -m 755 -p /server/{backup,data,steamcmd/home/.fex-emu,starbound/{assets,mods,storage,logs,steamapps}} && \
    groupadd -g 1000 steam && \
    useradd -u 1000 -g steam -d /server/steamcmd/home steam && \
    chown -R steam:steam /server

USER steam
WORKDIR /server
COPY --chown=root:root   --chmod=755 --from=builder-fex           /output/fex           /usr/bin
COPY --chown=root:root   --chmod=755 --from=builder-fex-rootfs    /output/rootfs        /server/rootfs
COPY --chown=root:root   --chmod=755 --from=builder-box64         /output/box64         /
COPY --chown=steam:steam --chmod=755 --from=builder-osb           /output/openstarbound /server/openstarbound
COPY --chown=steam:steam --chmod=755 --from=builder-steam         /output/steamcmd      /server/steamcmd
COPY --chown=steam:steam --chmod=755                              starbound.sh          /server/
COPY --chown=steam:steam --chmod=755                              starbound.env         /server/data/
RUN echo '{"Config":{"RootFS":"/server/rootfs"}}' >/server/steamcmd/home/.fex-emu/Config.json
EXPOSE 21025/tcp
STOPSIGNAL SIGINT
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/server/starbound.sh"]
