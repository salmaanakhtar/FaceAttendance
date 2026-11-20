-- Yabil operates in South Africa. The original demo seed incorrectly used
-- Asia/Karachi (UTC+5), making kiosk clocks three hours fast.
UPDATE orgs
SET timezone = 'Africa/Johannesburg'
WHERE slug = 'yabil'
  AND timezone = 'Asia/Karachi';

UPDATE sites
SET timezone = 'Africa/Johannesburg'
WHERE org_id IN (SELECT id FROM orgs WHERE slug = 'yabil')
  AND timezone = 'Asia/Karachi';
