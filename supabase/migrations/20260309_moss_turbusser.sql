-- 1. Opprett selskapet
INSERT INTO companies (id, name)
VALUES (gen_random_uuid(), 'Moss Turbusser')
ON CONFLICT DO NOTHING;

-- 2. Legg til michael@nttas.com som admin med css-modus
INSERT INTO company_members (company_id, user_id, role, app_mode)
SELECT c.id, p.id, 'admin', 'css'
FROM companies c, profiles p
WHERE c.name = 'Moss Turbusser'
  AND p.email = 'michael@nttas.com'
ON CONFLICT DO NOTHING;
