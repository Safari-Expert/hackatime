# Self-hosted Railway deploy

This fork supports a Safari Expert self-hosted mode for Railway-backed deployments.

## Service layout

Deploy two services in the `Meister Core` Railway project:

- `hackatime-web`: deploy from this repo with the root `Dockerfile`
- `hackatime-worker`: deploy from this repo with `Dockerfile.production-worker`

Use the same dedicated Hackatime Postgres database/user for both services. Expose only `hackatime-web` publicly and use `/up` for health checks.

In Safari Expert self-host mode, production cache and Action Cable also use that same Postgres database so the Railway deploy does not depend on local SQLite files.

## Required environment variables

Set these on both services:

- `RAILS_ENV=production`
- `APP_HOST=<public-hostname-only>`
- `DATABASE_URL=<dedicated direct Postgres URL>`
- `POOL_DATABASE_URL=<dedicated pooled Postgres URL or same direct URL>`
- `SAILORS_LOG_DATABASE_URL=<same dedicated Hackatime Postgres URL>`
- `SECRET_KEY_BASE=<generated secret>`
- `RAILS_MASTER_KEY=<config/master.key value>`
- `ENCRYPTION_PRIMARY_KEY=<generated secret>`
- `ENCRYPTION_DETERMINISTIC_KEY=<generated secret>`
- `ENCRYPTION_KEY_DERIVATION_SALT=<generated secret>`
- `SAFARI_EXPERT_SELF_HOSTED=true`

Set storage explicitly:

- `ACTIVE_STORAGE_SERVICE=local` for the default Railway volume-based setup
- `ACTIVE_STORAGE_SERVICE=r2` if you want R2-backed Active Storage instead

For the default local-disk path, mount a writable Railway volume on `hackatime-web` at `/rails/storage`.

## Optional R2 storage

If you provision an R2 bucket, switch `ACTIVE_STORAGE_SERVICE` to `r2` and add:

- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `S3_ENDPOINT`

The app already supports `local` and `r2` through `config/storage.yml`. V1 can start on local storage and switch to R2 later without further code changes.

## Bootstrap admin and API keys

Run the bootstrap task once against `hackatime-web` after the first successful deploy:

```bash
bundle exec rails safari_expert:bootstrap_admin
```

Set these env vars before you run it:

- `SAFARI_EXPERT_BOOTSTRAP_ADMIN_EMAIL`
- `SAFARI_EXPERT_BOOTSTRAP_ADMIN_USERNAME` optional, defaults to the email local-part
- `SAFARI_EXPERT_BOOTSTRAP_ADMIN_TIMEZONE` optional, defaults to `Africa/Nairobi`
- `SAFARI_EXPERT_BOOTSTRAP_ADMIN_API_KEY_NAME` optional
- `SAFARI_EXPERT_BOOTSTRAP_USER_API_KEY_NAME` optional
- `SAFARI_EXPERT_BOOTSTRAP_SIGN_IN_TTL_DAYS` optional, defaults to `365`

The task is idempotent and prints:

- one-time sign-in URL using `/auth/token/:token`
- admin API key for `internal_ui`
- user API key for WakaTime-compatible client testing

## `internal_ui` wiring

Feed the printed admin API key and public URL into `internal_ui`:

- `INTERNAL_UI_HACKATIME_URL`
- `INTERNAL_UI_HACKATIME_API_URL`
- `INTERNAL_UI_HACKATIME_ADMIN_API_KEY`
- `INTERNAL_UI_HACKATIME_SNAPSHOT_SECRET`

Then point the VS Code WakaTime plugin and `terminal-wakatime` at:

```text
https://<hackatime-public-domain>/api/hackatime/v1
```

Use the printed user API key for the first end-to-end heartbeat test.
