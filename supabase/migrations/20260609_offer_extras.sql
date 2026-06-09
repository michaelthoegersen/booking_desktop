-- Ekstrakostnader (extra cost line items) for offers.
-- A list of {name, amount} objects that the user can name freely (e.g.
-- "Komponering for produksjon"). Stored on the offer; the per-item amounts
-- flow into the offer's final_calc and the Intensjonsavtale price summary on
-- equal footing with shows. Face value — no markup is applied.

alter table gig_offers
  add column if not exists extras jsonb not null default '[]'::jsonb;
