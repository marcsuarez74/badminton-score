-- 20260922000001 — Support double/mixte : type de match et partenaires.
-- devices : format du match + 2ᵉ joueur par équipe (vides en simple).
ALTER TABLE devices ADD COLUMN IF NOT EXISTS format text NOT NULL DEFAULT 'simple';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS name1b text NOT NULL DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS name2b text NOT NULL DEFAULT '';
