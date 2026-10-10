# Native multi-arch PostGIS: official postgres image + PostGIS from the PGDG apt repo
# (postgis/postgis has no arm64 build; see plan D-010).
FROM docker.io/library/postgres:17
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-17-postgis-3 \
    && rm -rf /var/lib/apt/lists/*
