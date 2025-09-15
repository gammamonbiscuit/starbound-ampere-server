FROM debian:trixie-slim AS builder
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/compile/vcpkg \
    OPENSTARBOUND_VERSION=v0.1.14
COPY OpenStarbound-ARM /OpenStarbound-ARM
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,target=/var/cache/debconf \
    apt update && \
    apt install -y curl ca-certificates zip unzip tar git build-essential cmake pkg-config libxmu-dev libxi-dev libgl-dev libglu1-mesa-dev libsdl2-dev python3-jinja2 ninja-build autoconf automake autoconf-archive libltdl-dev && \
    mkdir -p /{compile,output}
WORKDIR /compile
RUN git clone --depth 1 https://github.com/ptitSeb/box64.git && \
    cd /compile/box64 && \
    cmake . -D ADLINK=1 -D ARM_DYNAREC=ON -D BOX32=ON -D BOX32_BINFMT=ON -D CMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install DESTDIR=/output/box64
RUN git clone --depth 1 https://github.com/microsoft/vcpkg.git && \
    cd /compile/vcpkg && \
    ./bootstrap-vcpkg.sh -disableMetrics
RUN git clone --depth 1 --branch ${OPENSTARBOUND_VERSION} https://github.com/OpenStarbound/OpenStarbound.git && \
    cp -R /OpenStarbound-ARM/. /compile/OpenStarbound/ && \
    cd /compile/OpenStarbound/source && \
    cmake --preset=linux-arm-release
RUN cd /compile/OpenStarbound/build/linux-arm-release && \
    cmake --build . --parallel $(nproc) && \
    cd /compile/OpenStarbound && \
    ./scripts/ci/linux/assemble.sh && \
    mv server_distribution /output/openstarbound

FROM debian:trixie-slim
SHELL ["/bin/bash", "-c"]
ARG DOCKER_BUILD=true
ENV BOX64_LOG=0 \
    BOX64_NOBANNER=1 \
    STEAM_LOGIN="anonymous" \
    OPENSTARBOUND=true \
    LAUNCH_GAME=true \
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
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,target=/var/cache/debconf \
    apt update && \
    apt install -y --no-install-recommends curl jq ca-certificates dumb-init
RUN mkdir -m 755 -p /server/{steamcmd/home,starbound/{assets,mods,storage,logs,steamapps}} && \
    groupadd -g 1000 steam && \
    useradd -u 1000 -g steam -d /server/steamcmd/home steam && \
    chown -R steam:steam /server
USER steam
WORKDIR /server
COPY --chown=root:root   --chmod=755 --from=builder  /output/box64 /
COPY --chown=steam:steam --chmod=755 --from=builder /output/openstarbound /server/openstarbound
COPY --chown=steam:steam --chmod=755 starbound.sh starbound.env /server/
#RUN /server/starbound.sh # To include SteamCMD and OpenStarbound components in /server
EXPOSE 21025/tcp
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/server/starbound.sh"]
