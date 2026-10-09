-- "Reise mit Etappen" (multi-leg journeys) – docs/JOURNEYS.md, contract §3.5.
-- Every leg stays a trip; the legs of one journey share `journey_id` (lowercase UUID, '' = a trip of its own) and keep
-- their travel order in `leg_index`. A favourite's `legs` holds its Kombi-Vorlage (JourneyLegCodec JSON, '' = one route).
-- Additive: older Workers never select the columns, older apps never send them (schema kind K keeps the stored value).
ALTER TABLE trips ADD COLUMN journey_id TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN leg_index INTEGER NOT NULL DEFAULT 0;
ALTER TABLE favorite_routes ADD COLUMN legs TEXT NOT NULL DEFAULT '';
