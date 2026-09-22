-- 20260922000002 — devices.id auto-incrémenté (les premières lignes étaient
-- créées à la main : id=1, 2 — sans séquence, tout INSERT à l'aveugle
-- violait devices_pkey avec id=1).
CREATE SEQUENCE IF NOT EXISTS devices_id_seq OWNED BY devices.id;
SELECT setval('devices_id_seq', (SELECT COALESCE(MAX(id), 0) FROM devices));
ALTER TABLE devices ALTER COLUMN id SET DEFAULT nextval('devices_id_seq');
ALTER TABLE devices ALTER COLUMN id SET NOT NULL;
