-- IRFAN GLOBAL ESTATES & DEVELOPERS: Supabase schema, RLS and storage. Run once in the SQL Editor.
create table public.profiles(id uuid primary key references auth.users on delete cascade, full_name text, role text not null default 'user' check(role in('user','admin')), created_at timestamptz not null default now());
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
create function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;
create function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

-- Hierarchy: country > city > society > phase > sector > block (one self-referencing table, unlimited growth, no hardcoding)
create type public.loc_type as enum('country','city','society','phase','sector','block');
create table public.locations(id bigint generated always as identity primary key, parent_id bigint references public.locations(id) on delete cascade,
 type public.loc_type not null, name text not null check(length(name) between 1 and 120), created_at timestamptz not null default now());
create unique index locations_unique on public.locations(coalesce(parent_id,0),type,lower(name));
create index locations_parent on public.locations(parent_id,type);

create table public.properties(id uuid primary key default gen_random_uuid(),
 code text unique not null default('IGE-P-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))),
 title text not null check(length(title) between 3 and 160), description text check(length(description)<=10000),
 category text not null check(category in('residential','commercial')), property_type text not null,
 purpose text not null default 'sale' check(purpose in('sale','rent')),
 price_pkr numeric(16,0) not null check(price_pkr>=0), size_value numeric(12,2) check(size_value>=0), size_unit text default 'marla',
 bedrooms int check(bedrooms>=0), bathrooms int check(bathrooms>=0),
 city_id bigint references public.locations(id), society_id bigint references public.locations(id), phase_id bigint references public.locations(id),
 sector_id bigint references public.locations(id), block_id bigint references public.locations(id), address text,
 amenities text[] not null default '{}', availability text not null default 'available' check(availability in('available','under_offer','sold','rented')),
 verification_status text not null default 'unverified' check(verification_status in('unverified','verified')),
 is_published boolean not null default false, is_featured boolean not null default false,
 created_by uuid references auth.users, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index properties_pub on public.properties(is_published,created_at desc);
create index properties_city on public.properties(city_id,society_id);
create index properties_price on public.properties(price_pkr);
create trigger properties_upd before update on public.properties for each row execute function public.set_updated_at();

create table public.property_media(id uuid primary key default gen_random_uuid(), property_id uuid not null references public.properties(id) on delete cascade,
 kind text not null check(kind in('image','video')), path text not null, sort int not null default 0, created_at timestamptz not null default now());
create index property_media_prop on public.property_media(property_id,sort);

create table public.enquiries(id uuid primary key default gen_random_uuid(), reference text unique not null,
 type text not null check(type in('buy','sell','overseas','commercial','construction','investment','contact')),
 name text not null, email text, phone text not null, country text, message text, details jsonb not null default '{}',
 status text not null default 'new' check(status in('new','contacted','in_progress','converted','closed')), admin_notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index enquiries_list on public.enquiries(status,created_at desc);
create trigger enquiries_upd before update on public.enquiries for each row execute function public.set_updated_at();

create table public.projects(id uuid primary key default gen_random_uuid(), title text not null, location text, category text, description text,
 progress int not null default 0 check(progress between 0 and 100), status text not null default 'planned' check(status in('planned','ongoing','completed')),
 cover_path text, is_published boolean not null default false, created_at timestamptz not null default now());
create table public.website_settings(key text primary key, value jsonb not null, updated_at timestamptz not null default now());

-- Public enquiry submission: validated, rate-limited, returns the reference ID. Public users cannot read enquiries.
create function public.submit_enquiry(p_type text, p_data jsonb) returns text language plpgsql security definer set search_path=public as $$
declare ref text; nm text:=trim(coalesce(p_data->>'name','')); ph text:=trim(coalesce(p_data->>'phone','')); em text:=nullif(trim(coalesce(p_data->>'email','')),'');
begin
 if p_type not in('buy','sell','overseas','commercial','construction','investment','contact') then raise exception 'invalid type'; end if;
 if length(nm) not between 2 and 120 then raise exception 'invalid name'; end if;
 if ph !~ '^\+?[0-9 ()-]{7,20}$' then raise exception 'invalid phone'; end if;
 if em is not null and em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
 if length(p_data::text)>8000 then raise exception 'too large'; end if;
 if (select count(*) from enquiries where phone=ph and created_at>now()-interval '1 hour')>=5 then raise exception 'rate limited'; end if;
 ref:='IGE-'||to_char(now() at time zone 'Asia/Karachi','YYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into enquiries(reference,type,name,email,phone,country,message,details) values(ref,p_type,nm,em,ph,left(p_data->>'country',80),left(p_data->>'msg',4000),p_data);
 return ref;
end $$;
revoke all on function public.submit_enquiry(text,jsonb) from public;
grant execute on function public.submit_enquiry(text,jsonb) to anon,authenticated;

-- Row Level Security
alter table public.profiles enable row level security; alter table public.locations enable row level security; alter table public.properties enable row level security;
alter table public.property_media enable row level security; alter table public.enquiries enable row level security; alter table public.projects enable row level security;
alter table public.website_settings enable row level security;
revoke all on public.enquiries from anon;
create policy profiles_read on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy profiles_admin on public.profiles for update using(public.is_admin()) with check(public.is_admin());
create policy loc_read on public.locations for select using(true);
create policy loc_admin on public.locations for all using(public.is_admin()) with check(public.is_admin());
create policy prop_read on public.properties for select using(is_published or public.is_admin());
create policy prop_admin on public.properties for all using(public.is_admin()) with check(public.is_admin());
create policy media_read on public.property_media for select using(public.is_admin() or exists(select 1 from public.properties p where p.id=property_id and p.is_published));
create policy media_admin on public.property_media for all using(public.is_admin()) with check(public.is_admin());
create policy enq_admin on public.enquiries for all using(public.is_admin()) with check(public.is_admin());
create policy proj_read on public.projects for select using(is_published or public.is_admin());
create policy proj_admin on public.projects for all using(public.is_admin()) with check(public.is_admin());
create policy set_read on public.website_settings for select using(true);
create policy set_admin on public.website_settings for all using(public.is_admin()) with check(public.is_admin());

-- Storage: public read, admin-only write; images and mp4 only, 50 MB cap
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('property-media','property-media',true,52428800,array['image/jpeg','image/png','image/webp','video/mp4'])
on conflict(id) do update set public=true,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
create policy media_obj_read on storage.objects for select using(bucket_id='property-media');
create policy media_obj_ins on storage.objects for insert to authenticated with check(bucket_id='property-media' and public.is_admin());
create policy media_obj_upd on storage.objects for update to authenticated using(bucket_id='property-media' and public.is_admin());
create policy media_obj_del on storage.objects for delete to authenticated using(bucket_id='property-media' and public.is_admin());

-- Reference locations (real places named in the site; no listings are created)
insert into public.locations(type,name) values('country','Pakistan');
insert into public.locations(parent_id,type,name) select (select id from public.locations where type='country'),'city'::public.loc_type,c from unnest(array['Islamabad','Rawalpindi','Lahore','Karachi','Peshawar','Multan']) c;
insert into public.locations(parent_id,type,name) select l.id,'society'::public.loc_type,v.s from public.locations l join (values('Rawalpindi','Bahria Town'),('Islamabad','Bahria Town'),('Lahore','Bahria Town'),('Karachi','Bahria Town'),('Peshawar','Bahria Town'),('Islamabad','DHA'),('Rawalpindi','DHA'),('Lahore','DHA'),('Karachi','DHA'),('Multan','DHA'),('Peshawar','DHA')) v(c,s) on l.type='city' and l.name=v.c;

-- FIRST ADMIN: create the user in Authentication > Users, then run (with your email):
-- update public.profiles set role='admin' where id=(select id from auth.users where email='you@example.com');
