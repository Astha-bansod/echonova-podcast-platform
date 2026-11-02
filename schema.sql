-- ECHONOVA schema. Run once in Supabase SQL Editor.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-zA-Z0-9_]{3,24}$'),
  bio text default '' check (char_length(bio) <= 280),
  avatar_path text,
  affiliation text default '',            -- self-declared, NOT verified
  verified boolean not null default false, -- admin-set only
  can_publish boolean not null default true,
  suspended boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'moderator' check (role in ('moderator','admin'))
);
create table public.categories (
  id serial primary key, name text unique not null
);
create table public.media_posts (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text default '' check (char_length(description) <= 2000),
  category_id int references public.categories(id),
  tags text[] not null default '{}',
  kind text not null check (kind in ('audio','video','photo','document')),
  visibility text not null default 'community' check (visibility in ('public','community','private')),
  status text not null default 'draft' check (status in ('draft','published','removed')),
  file_path text not null, file_mime text not null, file_size bigint not null check (file_size > 0),
  cover_path text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index on media_posts (status, visibility, created_at desc);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.media_posts(id) on delete cascade,
  reporter uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now(),
  unique (post_id, reporter)
);
create table public.announcements (  -- OFFICIAL notices; admins only
  id uuid primary key default gen_random_uuid(),
  title text not null, body text not null,
  author uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  note text not null, status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create function public.is_admin() returns boolean language sql security definer stable set search_path = public as
$$ select exists(select 1 from admin_roles where user_id = auth.uid()) $$;
create function public.touch() returns trigger language plpgsql as
$$ begin new.updated_at = now(); return new; end $$;
create trigger t_touch before update on media_posts for each row execute function touch();

-- Block users from self-escalating protected profile columns
create function public.guard_profile() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    new.verified := old.verified; new.can_publish := old.can_publish; new.suspended := old.suspended;
  end if;
  return new;
end $$;
create trigger t_guard before update on profiles for each row execute function guard_profile();
create function public.guard_insert() returns trigger language plpgsql as $$
begin new.verified:=false; new.suspended:=false; new.can_publish:=true; return new; end $$;
create trigger t_guard_i before insert on profiles for each row execute function guard_insert();

alter table profiles enable row level security;
alter table admin_roles enable row level security;
alter table categories enable row level security;
alter table media_posts enable row level security;
alter table reports enable row level security;
alter table announcements enable row level security;
alter table verification_requests enable row level security;

create policy "profiles read" on profiles for select using (true);  -- no phone stored here
create policy "profiles insert own" on profiles for insert with check (id = auth.uid());
create policy "profiles update own/admin" on profiles for update using (id = auth.uid() or is_admin());
create policy "admin_roles self read" on admin_roles for select using (user_id = auth.uid());
create policy "categories read" on categories for select using (true);
create policy "categories admin" on categories for all using (is_admin()) with check (is_admin());

create policy "posts read" on media_posts for select using (
  owner = auth.uid() or is_admin() or (status = 'published' and (visibility = 'public' or (visibility = 'community' and auth.uid() is not null)))
);
create policy "posts insert" on media_posts for insert with check (
  owner = auth.uid() and exists (select 1 from profiles p where p.id = auth.uid() and p.can_publish and not p.suspended)
);
create policy "posts update own" on media_posts for update using (owner = auth.uid() and status <> 'removed') with check (owner = auth.uid() and status <> 'removed');
create policy "posts moderate" on media_posts for update using (is_admin());
create policy "posts delete own/admin" on media_posts for delete using (owner = auth.uid() or is_admin());

create policy "reports insert" on reports for insert with check (reporter = auth.uid());
create policy "reports admin read" on reports for select using (is_admin());
create policy "reports admin update" on reports for update using (is_admin());
create policy "ann read" on announcements for select using (true);
create policy "ann admin write" on announcements for all using (is_admin()) with check (is_admin() and author = auth.uid());
create policy "vr own insert" on verification_requests for insert with check (user_id = auth.uid());
create policy "vr read" on verification_requests for select using (user_id = auth.uid() or is_admin());
create policy "vr admin update" on verification_requests for update using (is_admin());

-- Storage: ONE private bucket, objects at <user_id>/<random>.<ext>. Access via signed URLs only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
 ('media','media',false, 52428800, array['audio/mpeg','audio/mp4','audio/wav','audio/ogg','video/mp4','video/webm','image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "media upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id='media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "media delete own" on storage.objects for delete to authenticated
  using (bucket_id='media' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));
create policy "media read allowed" on storage.objects for select using (
  bucket_id='media' and (
    (storage.foldername(name))[1] = auth.uid()::text or is_admin() or
    exists (select 1 from media_posts p where (p.file_path = name or p.cover_path = name) and p.status='published'
            and (p.visibility='public' or (p.visibility='community' and auth.uid() is not null)))
  ));

insert into categories(name) values ('Campus Life'),('Technology'),('Career'),('Arts & Culture'),('Sports'),('Academics') on conflict do nothing;
-- Make yourself admin AFTER signing up once:
-- insert into admin_roles(user_id, role) select id,'admin' from auth.users where phone = '91XXXXXXXXXX';
