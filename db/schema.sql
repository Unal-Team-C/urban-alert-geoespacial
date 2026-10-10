-- Geospatial service schema. Applied by db/init/01_init.sh on an empty volume.
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS coordinates (
    coordinate_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     uuid NOT NULL,
    location      geography(Point, 4326) NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT coordinates_report_id_key UNIQUE (report_id)
);

CREATE INDEX IF NOT EXISTS coordinates_location_gix ON coordinates USING GIST (location);
