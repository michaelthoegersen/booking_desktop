-- Per-unit registration is now opt-in, and you choose WHICH fields are kept
-- per unit (serial number, size, comment, or one field you name yourself).
--
-- unit_fields holds the chosen field definitions for the item, e.g.
--   [{"key": "sn", "label": "Serienr."}, {"key": "note", "label": "Kommentar"}]
-- NULL or an empty array means the item is tracked by quantity only — no
-- per-unit rows at all. That is the new default, so adding 10 kjeledresser no
-- longer forces 10 serial-number fields.
--
-- The existing "serials" column keeps its name and its shape: a JSON array
-- with one object per unit. Those objects are now keyed by the field keys in
-- unit_fields, which makes the old {"sn": ..., "note": ...} rows valid as they
-- stand. Items that already have serials but no unit_fields are read as
-- serial number + comment, exactly as before.

alter table public.mgmt_inventory_items
  add column if not exists unit_fields jsonb;

alter table public.logistics_inventory_items
  add column if not exists unit_fields jsonb;
