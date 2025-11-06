FROM debian:trixie-slim AS base

SHELL ["/bin/bash", "-c"]

ARG TARGETPLATFORM \
    DOCKER_BUILD=true \
    DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/compile/vcpkg \
    OPENSTARBOUND_VERSION=v0.1.14

RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,target=/var/cache/debconf \
    apt update && \
    apt install -y --no-install-recommends curl ca-certificates zip unzip tar git jq $([[ "$TARGETPLATFORM" == "linux/amd64" ]] && echo "lib32stdc++6")

FROM base AS builder

COPY OpenStarbound-ARM /OpenStarbound-ARM

RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,target=/var/cache/debconf \
    if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        apt install -y build-essential cmake pkg-config libxmu-dev libxi-dev libgl-dev libglu1-mesa-dev libsdl2-dev python3-jinja2 ninja-build autoconf automake autoconf-archive libltdl-dev; \
    fi

RUN mkdir -p /{compile,output/box64}

WORKDIR /compile

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
        git clone --depth 1 --branch ${OPENSTARBOUND_VERSION} https://github.com/OpenStarbound/OpenStarbound.git && \
        cp -R /OpenStarbound-ARM/. /compile/OpenStarbound/ && \
        cd /compile/OpenStarbound/source && \
        cmake --preset=linux-arm-release; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/arm64" ]]; then \
        cd /compile/OpenStarbound/build/linux-arm-release && \
        cmake --build . --parallel $(nproc) && \
        cd /compile/OpenStarbound && \
        ./scripts/ci/linux/assemble.sh && \
        mv server_distribution /output/openstarbound; \
    fi

RUN if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then \
        curl -L -O "https://github.com/OpenStarbound/OpenStarbound/releases/download/${OPENSTARBOUND_VERSION}/OpenStarbound-Linux-Clang-Server.zip" && \
        unzip "OpenStarbound-Linux-Clang-Server.zip" && \
        curl -L -O "https://github.com/OpenStarbound/OpenStarbound/releases/download/${OPENSTARBOUND_VERSION}/OpenStarbound-Linux-Clang-Client.zip" && \
        unzip "OpenStarbound-Linux-Clang-Client.zip" && \
        if [[ -f "server.tar" && -f "client.tar" ]]; then \
            tar xvf "server.tar" && \
            tar xvf "client.tar" && \
            mv server_distribution /output/openstarbound && \
            mv client_distribution/linux/asset_packer /output/openstarbound/linux/asset_packer && \
            mv client_distribution/linux/asset_unpacker /output/openstarbound/linux/asset_unpacker && \
            rm /output/openstarbound/mods/mods_go_here; \
        else \
            exit 1; \
        fi \
    fi

FROM base AS final

ENV BOX64_LOG=0 \
    BOX64_NOBANNER=1 \
    STEAM_LOGIN="anonymous" \
    OPENSTARBOUND=true \
    LAUNCH_GAME=true \
    BACKUP_ENABLED=true \
    BACKUP_VERSIONS=10 \
    BACKUP_MODS_MANUAL=false \
    BACKUP_MODS_WORKSHOP=false \
    UPDATE_GAME=false \
    UPDATE_WORKSHOP=false \
    UPDATE_WORKSHOP_FORCE=false \
    WORKSHOP_ITEMS="" \
    WORKSHOP_COLLECTIONS="" \
    WORKSHOP_CHUNK=20 \
    WORKSHOP_PRUNE=true \
    WORKSHOP_MAX_RETRY=3 \
    BOX64_DYNAREC_STRONGMEM=1 \
    BOX64_DYNAREC_BIGBLOCK=1 \
    BOX64_DYNAREC_SAFEFLAGS=1 \
    BOX64_DYNAREC_FASTROUND=1 \
    BOX64_DYNAREC_FASTNAN=1 \
    BOX64_DYNAREC_X87DOUBLE=0

RUN mkdir -m 755 -p /server/{backup,steamcmd/home,starbound/{assets,mods,storage,logs,steamapps}} && \
    groupadd -g 1000 steam && \
    useradd -u 1000 -g steam -d /server/steamcmd/home steam && \
    chown -R steam:steam /server

USER steam
WORKDIR /server
COPY --chown=root:root   --chmod=755 --from=builder-box64  /output/box64 /
COPY --chown=steam:steam --chmod=755 --from=builder-osb    /output/openstarbound /server/openstarbound
COPY --chown=steam:steam --chmod=755 starbound.sh starbound.env /server/

RUN if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then \
        sed -ir "s/box64\s/\.\//g" /server/starbound.sh && \
        sed -ir "s/\sARM\s/ x86 /g" /server/starbound.sh; \
    fi
#RUN /server/starbound.sh # To include SteamCMD and OpenStarbound components in /server
EXPOSE 21025/tcp
STOPSIGNAL SIGINT
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/server/starbound.sh"]
