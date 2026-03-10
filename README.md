# Expense Tracker (Flutter + Node + Neon PostgreSQL)

This project is a Splitwise-style expense tracker for friend trips.

## Features Implemented

- Create trip/expense groups.
- Join groups with invite token link logic.
- Login with only name + phone (no password).
- Session-based auth with `express-session`, 30-day session cookie.
- Add expenses with flexible payers and split rows.
- Upload attachment/image for expenses via AWS S3 presigned URL.
- Group-level balances (`you owe` or `you should get`).
- Expense activity feed per group.
- SQL migration files for Neon PostgreSQL.

## Project Structure

- `server/`: Node.js + Express + Passport + PostgreSQL API
- `app/`: Flutter mobile client

## Backend Setup (`server`)

1. Open terminal in `server`.
2. Install packages:
   - `npm install`
3. Copy env file:
   - `copy .env.example .env`
4. Fill `.env` values:
   - `DATABASE_URL` (Neon connection string)
   - `SESSION_SECRET`
   - `CLIENT_ORIGIN`
   - `AWS_*` keys and bucket settings
5. Run migrations:
   - `npm run migrate`
6. Start server:
   - `npm run dev`

Server will run on `http://localhost:4000`.

## Flutter Setup (`app`)

1. Open terminal in `app`.
2. Get dependencies:
   - `flutter pub get`
3. Run app:
   - `flutter run`

By default Android emulator calls server at `http://10.0.2.2:4000`.
If using real phone, update `baseUrl` in `app/lib/services/api_service.dart`.

## Invite Link Behavior

- API returns invite token when group is created.
- You can create new invite tokens from group detail.
- App currently uses token input.
- You can convert it to URL format in UI, e.g.:
  - `myapp://join?token=<inviteToken>`
  - or web deep link `https://yourdomain/join/<inviteToken>`

## Login Behavior

- User enters name + phone.
- Backend checks exact phone and case-insensitive name match in `users` table.
- Users are expected to be manually inserted by you in DB (as requested).

## Sessions

- Stored in PostgreSQL table `user_sessions`.
- Cookie/session expiry configured to 30 days.

## Important API Endpoints

- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/groups`
- `POST /api/groups/join`
- `GET /api/groups`
- `GET /api/groups/:groupId`
- `POST /api/groups/:groupId/invites`
- `POST /api/groups/:groupId/expenses`
- `GET /api/groups/:groupId/expenses`
- `GET /api/groups/:groupId/summary`
- `POST /api/uploads/presign`
- `POST /api/expenses/:expenseId/attachments`

## Migrations Included

- `server/migrations/001_init.sql`
- `server/migrations/002_indexes.sql`
- `server/migrations/003_seed_sample_users.sql` (optional seed)

## Notes

- This is a strong starter scaffold with core flows done.
- Advanced split modes (unequally, percentages, shares, adjustments) can be layered by changing UI + split generation payload in Flutter.
- Push notifications, receipt OCR, and proper deep-link invite flow can be added next.
