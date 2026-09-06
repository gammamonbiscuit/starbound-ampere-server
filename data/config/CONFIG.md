## Server Config
Here is the place to edit container's config, by editing the `config.env` or `sbinit_defaults.config`.
- An example `config.env.example` is provided with default values.
- If `config.env` doesn't exist when starting the container, it will create one.
- If an config entry doesn't exist in `config.env`, container will use the one baked in the image.
- In most cases you don't need to edit `sbinit_defaults.config`.