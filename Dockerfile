FROM scratch AS init

ARG TARGETPLATFORM \
    DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/compile/vcpkg

ENV OPENSTARBOUND_VERSION=v0.1.14 \
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
    FEX_ENABLED=true \
    FEX_ROOTFS_IN_TMP=true \
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
    apt install -y --no-install-recommends curl ca-certificates zip unzip tar git jq $([[ "$TARGETPLATFORM" == "linux/arm64" && "$FEX_ENABLED" == true ]] && echo "squashfs-tools") $([[ "$TARGETPLATFORM" == "linux/amd64" ]] && echo "lib32stdc++6")

FROM base AS builder

COPY OpenStarbound-ARM /OpenStarbound-ARM

RUN --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,id=apt-trixie-$TARGETPLATFORM,sharing=locked,target=/var/cache/debconf \
    if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        apt install -y build-essential cmake pkg-config libxmu-dev libxi-dev libgl-dev libglu1-mesa-dev libsdl2-dev python3-jinja2 ninja-build autoconf automake autoconf-archive libltdl-dev; \
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
    if [[ "$TARGETPLATFORM" == "linux/arm64" && "$FEX_ENABLED" == true ]]; then \
        apt update && \
        apt install -y git cmake lld clang llvm ninja-build pkg-config libsdl2-dev qtbase5-dev qtdeclarative5-dev && \
        git clone --depth 1 --recurse-submodules https://github.com/FEX-Emu/FEX.git && \
        cd /compile/FEX && \
        mkdir build && \
        CC=clang CXX=clang++ cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True -DBUILD_TESTING=False -DENABLE_ASSERTIONS=False -G Ninja . && \
        ninja -j$(nproc) && \
        mv /compile/FEX/Bin/* /output/fex; \
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
        git clone --depth 1 https://github.com/microsoft/vcpkg.git && \
        cd /compile/vcpkg && \
        ./bootstrap-vcpkg.sh -disableMetrics; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        git clone --depth 1 --branch ${OPENSTARBOUND_VERSION:-main} https://github.com/OpenStarbound/OpenStarbound.git && \
        cp -R /OpenStarbound-ARM/. /compile/OpenStarbound/ && \
        cd /compile/OpenStarbound/source && \
        cmake --preset=linux-arm-release; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
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
COPY --chown=root:root   --chmod=755 --from=builder-fex    /output/fex           /usr/bin/
COPY --chown=root:root   --chmod=755 --from=builder-box64  /output/box64         /
COPY --chown=steam:steam --chmod=755 --from=builder-osb    /output/openstarbound /server/openstarbound
COPY --chown=steam:steam --chmod=755 --from=builder-steam  /output/steamcmd      /server/steamcmd
COPY --chown=steam:steam --chmod=755                       starbound.sh          /server/
COPY --chown=steam:steam --chmod=755                       starbound.env         /server/data/
RUN if [[ "$TARGETPLATFORM" == "linux/arm64" && "$FEX_ENABLED" == true ]]; then \
        if [[ ! "$FEX_ROOTFS_IN_TMP" == true ]]; then \
            FEXRootFSFetcher -y -x --distro-name=ubuntu --distro-version=24.04 && \
            rm /server/steamcmd/home/.fex-emu/RootFS/*.sqsh; \
        fi; \
    fi
EXPOSE 21025/tcp
STOPSIGNAL SIGINT
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/server/starbound.sh"]
