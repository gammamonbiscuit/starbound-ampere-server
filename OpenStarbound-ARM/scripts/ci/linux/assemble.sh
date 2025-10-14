#!/bin/sh -e
# Modified and stripped down version of the original file  because we only need the server part.

mkdir server_distribution
mkdir server_distribution/assets
mkdir server_distribution/mods
./dist/asset_packer -c scripts/packing.config -s assets/opensb server_distribution/assets/opensb.pak
mkdir server_distribution/linux
cp \
  dist/starbound_server \
  dist/btree_repacker \
  dist/asset_packer \
  dist/asset_unpacker \
  scripts/ci/linux/run-server.sh \
  scripts/ci/linux/sbinit.config \
  scripts/steam_appid.txt \
  server_distribution/linux/