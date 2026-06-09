-- Ekstrakostnader (extra cost line items) for offers.
-- A list of objects the user can name freely (e.g. "Komponering for
-- produksjon"). Stored on the offer; the per-item amounts flow into the
-- offer's final_calc and the Intensjonsavtale price summary on equal footing
-- with shows. Face value — no markup is applied to the customer price.
--
-- Shape of each item:
--   {
--     "name":          text,
--     "amount":        number,           -- customer-facing price
--     "allocation":    "group" | "member" | "split",  -- payout side only
--     "member_id":     uuid,             -- for member/split
--     "member_name":   text,             -- cached display name
--     "member_amount": number            -- for split: kr to the member
--   }
-- The allocation only affects how the amount is paid out to band members on
-- the gigghyre (see mgmt_gig_hire_admin_page.dart); it never changes the
-- customer price.

alter table gig_offers
  add column if not exists extras jsonb not null default '[]'::jsonb;
