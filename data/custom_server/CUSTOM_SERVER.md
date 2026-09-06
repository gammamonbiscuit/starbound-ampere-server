## Custom Server
Here is the place where you can install custom build instead of using the one coming with the image.
- Expects OpenStarbound's file structure by default, edit `custom_server.env` if that's not the case.

```
custom-server
├── assets                  <-- CUSTOM_SERVER_ASSET_DIR
│   └── opensb.pak
├── linux
│   ├── asset_packer
│   ├── asset_unpacker
│   ├── btree_repacker
│   ├── run-server.sh
│   ├── sbinit.config
│   ├── starbound_server    <-- CUSTOM_SERVER_BINARY
│   └── steam_appid.txt
```