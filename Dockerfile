FROM debian:trixie-slim
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    BOX64_LOG=0 \
    BOX64_NOBANNER=1 \
    STEAM_LOGIN="anonymous" \
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
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    --mount=type=cache,target=/var/cache/debconf <<EOF
    apt update
    apt install -y --no-install-suggests locales python3 curl jq ca-certificates git build-essential cmake dumb-init libvorbisfile3
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    dpkg-reconfigure --frontend=noninteractive locales
    update-locale LANG=en_US.UTF-8
    mkdir -p /build
    cd /build
    git clone https://github.com/ptitSeb/box64.git
    cd /build/box64
    cmake . -D ADLINK=1 -D ARM_DYNAREC=ON -D BOX32=ON -D BOX32_BINFMT=ON -D CMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    make install
    cd /
    rm -rf /build
    apt purge -y python3 git build-essential cmake
    apt autoremove -y
EOF
RUN <<EOF
    rm -rf /server
    mkdir -m 755 -p /server/{steamcmd/home,starbound/{mods,storage,steamapps}}
    groupadd -g 1000 steam
    useradd -u 1000 -g steam -d /server/steamcmd/home steam
    chown -R steam:steam /server
EOF
USER steam
RUN <<EOF
    cd /server/steamcmd
    curl -L -O "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    tar zxvf steamcmd_linux.tar.gz
    rm steamcmd_linux.tar.gz
EOF
COPY --chown=steam:steam --chmod=755 starbound.sh /server/
COPY --chown=steam:steam --chmod=755 starbound.env /server/
EXPOSE 21025/tcp
WORKDIR /server
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/server/starbound.sh"]