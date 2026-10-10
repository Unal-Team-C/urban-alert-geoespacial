-- Seed data for local testing (main database only; never loaded into geospatial_test).
-- Deterministic: fixed demo points and a reproducible synthetic load set (setseed).

-- 31 demo reports across Bogotá (urban localities + Sumapaz).
INSERT INTO coordinates (report_id, location)
SELECT md5('demo-' || name)::uuid, ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
FROM (VALUES
    ('plaza-bolivar', 4.5981, -74.0761),
    ('la-candelaria', 4.5960, -74.0730),
    ('santa-fe', 4.6100, -74.0700),
    ('monserrate', 4.6058, -74.0556),
    ('chapinero', 4.6486, -74.0628),
    ('galerias', 4.6420, -74.0770),
    ('teusaquillo', 4.6360, -74.0830),
    ('parque-93', 4.6767, -74.0483),
    ('usaquen', 4.6950, -74.0310),
    ('unicentro', 4.7020, -74.0410),
    ('toberin', 4.7470, -74.0440),
    ('portal-norte', 4.7540, -74.0460),
    ('suba', 4.7410, -74.0840),
    ('calle-80', 4.6890, -74.0890),
    ('engativa', 4.7060, -74.1130),
    ('aeropuerto', 4.7016, -74.1469),
    ('fontibon', 4.6780, -74.1430),
    ('salitre', 4.6560, -74.1030),
    ('puente-aranda', 4.6150, -74.1180),
    ('kennedy', 4.6280, -74.1530),
    ('las-americas', 4.6180, -74.1360),
    ('tintal', 4.6440, -74.1630),
    ('bosa', 4.6190, -74.1880),
    ('antonio-narino', 4.5900, -74.1000),
    ('restrepo', 4.5880, -74.1050),
    ('rafael-uribe', 4.5730, -74.1150),
    ('tunal', 4.5730, -74.1350),
    ('san-cristobal', 4.5640, -74.0830),
    ('ciudad-bolivar', 4.5070, -74.1520),
    ('usme', 4.4720, -74.1260),
    ('sumapaz-nazareth', 4.1290, -74.2190)
) AS demo(name, lat, lon);

-- 20 000 synthetic reports uniformly spread over the urban area, for load tests (RNF-001).
SELECT setseed(0.42);

INSERT INTO coordinates (report_id, location)
SELECT md5('synthetic-' || i)::uuid,
       ST_SetSRID(ST_MakePoint(-74.20 + random() * 0.18, 4.47 + random() * 0.33), 4326)::geography
FROM generate_series(1, 20000) AS i;

ANALYZE coordinates;
