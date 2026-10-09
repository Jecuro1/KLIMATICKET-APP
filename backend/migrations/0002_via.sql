-- Via stops ("Über …", Zwischenhalte) of trips and favourite routes – docs/VIA.md, contract §3.5.
-- Additive: older Workers never select the column, older apps never send it (the Worker then keeps the stored value).
-- Encoding (TripViaCodec): one "<stationID>\t<name>" line per via in travel order, '' = direct route.
ALTER TABLE trips ADD COLUMN via TEXT NOT NULL DEFAULT '';
ALTER TABLE favorite_routes ADD COLUMN via TEXT NOT NULL DEFAULT '';
