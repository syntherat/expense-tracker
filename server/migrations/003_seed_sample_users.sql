-- Optional sample users for local testing. Remove this migration in production if not needed.
INSERT INTO users (full_name, phone)
VALUES
  ('Akshat Balariya', '8852944440'),
  ('Vanya Ahuja', '8528899772'),
  ('Mansi Singh', '8003040444'),
  ('Sounak Pal', '8116202373'),
  ('Radhika Tyagi', '7455080564'),
  ('Kanishka Agrawal', '7000882615'),
  ('Kristi Choudhury', '7630872659'),
  ('Kriti Sapkota', '9560260783'),
  ('Ashutosh Nanda', '7008311601')
ON CONFLICT (phone) DO NOTHING;
