# Irfan Global Estates & Developers: backend setup

Contents: `index.html` (your existing site, now database-connected), `admin.html` (dashboard), `config.js` (public keys), `supabase/schema.sql`, `.env.example`.

## 1. Create the Supabase project (free tier)
1. Create a project at supabase.com.
2. SQL Editor: paste and run `supabase/schema.sql` once (tables, RLS policies, `submit_enquiry` function, `property-media` storage bucket, reference cities and societies).
3. Authentication > Providers > Email: **turn off "Allow new users to sign up"** so only people you invite can log in.

## 2. Connect the website
Project Settings > API: copy the Project URL and the **anon public** key into `config.js`. Never use the service-role key in these files.

## 3. Create the first administrator
Authentication > Users > Add user (your email and a strong password). Then in the SQL Editor:

    update public.profiles set role='admin' where id=(select id from auth.users where email='YOU@EXAMPLE.COM');

Sign in at `/admin.html`. Anyone without role `admin` is signed out immediately and the database refuses their writes.

## 4. Deploy
Upload the folder to any static host (Netlify, Cloudflare Pages, Vercel, GitHub Pages). It cannot run as a Claude-published page, because those pages are blocked from contacting Supabase. In Supabase, add your site URL under Authentication > URL Configuration.

## How it works
- **Enquiries:** every form calls `submit_enquiry`, which validates, rate-limits (5 per phone per hour), stores the record and returns a unique reference (e.g. `IGE-261107-A1B2C3`). Public users cannot read enquiries.
- **Properties:** public users only see rows with `is_published = true`. Only admins write. Media goes to the `property-media` bucket (admin-only upload; JPG/PNG/WebP and MP4; 50 MB cap).
- **Locations:** one hierarchical table (country > city > society > phase > sector > block), managed in the admin Locations tab.
- **Empty database:** the site shows empty states. No fake listings exist.

## Testing report
**Checked:** JavaScript in `index.html` and `admin.html` passes a Node syntax check. The existing pages, styling and animations were left unchanged. The SQL was reviewed by hand.

**NOT tested** (no Supabase project or network was available): running the SQL, admin login, property create/edit/delete, image and video upload, publish/unpublish, listing filters and pagination, form submissions to the database, RLS behaviour, and mobile layout of the new sections. Expect to fix small issues on first run. Please go through that list after setup and send me any errors.

## Not implemented / needs you
- **Email notifications** (admin alert and customer confirmation): not built. They need an email provider account (e.g. Resend) and a Supabase Edge Function or database webhook. Until then, check the dashboard for new enquiries.
- **Currency display (USD/GBP/AED/CAD):** not built. It needs an exchange-rate API; listings show PKR only.
- **Phone input:** unchanged. It validates numbers with a country code typed in; there is no country-code dropdown yet.
- **Projects and website settings:** tables and security rules exist, but there is no admin screen or public display yet.
- **WhatsApp:** +92 321 5511200 is the number you gave me. I cannot verify that it is active; please test it.
- **Clean per-property URLs and sitemap:** detail pages use `#/property/ID`, which search engines index poorly. Server-rendered pages would need a framework.
