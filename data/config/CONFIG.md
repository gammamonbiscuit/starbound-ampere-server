## Server Config
Here is the place to edit container's config, by editing the `config.env` or `sbinit.config`.
- Examples `config.env.example` and `sbinit.config.example` are provided with default values.
- If `config.env` or `sbinit.config` doesn't exist when starting the container, it will create one.
- If an config entry doesn't exist in `config.env`, container will use the one baked in the image.
- In `sbinit.config`, `assetDirectories` and `storageDirectory` are overwritten on every start.