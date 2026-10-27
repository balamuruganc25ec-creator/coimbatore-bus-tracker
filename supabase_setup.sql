-- Coimbatore Transit: database setup
-- Run this complete script in Supabase Dashboard > SQL Editor.
-- Then create an Auth user and promote it to admin using the instructions in README.md.

create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.routes (
  id uuid primary key default gen_random_uuid(),
  route_code text not null unique,
  name text not null,
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stops (
  id uuid primary key default gen_random_uuid(),
  stop_code text unique,
  name text not null unique,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now(),
  constraint stop_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint stop_longitude_range check (longitude is null or longitude between -180 and 180)
);

create table if not exists public.route_stops (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes(id) on delete cascade,
  stop_id uuid not null references public.stops(id) on delete restrict,
  stop_order integer not null check (stop_order > 0),
  distance_from_previous_km numeric(8,3) not null default 0 check (distance_from_previous_km >= 0),
  boarding_min numeric(6,2) not null default 2 check (boarding_min >= 0),
  traffic_factor numeric(5,2) not null default 1.25 check (traffic_factor >= 1),
  extra_delay_min numeric(6,2) not null default 2 check (extra_delay_min >= 0),
  created_at timestamptz not null default now(),
  unique (route_id, stop_id),
  unique (route_id, stop_order)
);

create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes(id) on delete cascade,
  service_name text not null default 'Regular service',
  departure_time time not null,
  days_of_week smallint[] not null default array[0,1,2,3,4,5,6]::smallint[],
  is_active boolean not null default true,
  notes text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.buses (
  id uuid primary key default gen_random_uuid(),
  bus_code text not null unique,
  route_id uuid references public.routes(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.bus_assignments (
  bus_id uuid not null references public.buses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bus_id, user_id)
);

create table if not exists public.bus_locations (
  bus_id uuid primary key references public.buses(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  speed_kmph double precision,
  heading_degrees double precision,
  recorded_at timestamptz not null default now()
);

create index if not exists route_stops_route_order_idx on public.route_stops(route_id, stop_order);
create index if not exists schedules_route_departure_idx on public.schedules(route_id, departure_time);
create index if not exists buses_route_idx on public.buses(route_id);
create index if not exists bus_locations_recorded_at_idx on public.bus_locations(recorded_at desc);

-- A SECURITY DEFINER function avoids policy recursion when checking admin membership.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users au where au.user_id = (select auth.uid())
  );
$$;

create or replace function public.can_update_bus_location(p_bus_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.bus_assignments ba
    where ba.bus_id = p_bus_id and ba.user_id = (select auth.uid())
  );
$$;

-- GPS writes go through this function so users can only update buses they manage/are assigned.
create or replace function public.upsert_bus_location(
  p_bus_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_speed_kmph double precision default null,
  p_heading_degrees double precision default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.can_update_bus_location(p_bus_id) then
    raise exception 'Not authorized to update this bus location';
  end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Invalid GPS coordinates';
  end if;
  insert into public.bus_locations(bus_id, latitude, longitude, speed_kmph, heading_degrees, recorded_at)
  values (p_bus_id, p_latitude, p_longitude, p_speed_kmph, p_heading_degrees, now())
  on conflict (bus_id) do update set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    speed_kmph = excluded.speed_kmph,
    heading_degrees = excluded.heading_degrees,
    recorded_at = excluded.recorded_at;
end;
$$;

revoke all on function public.upsert_bus_location(uuid,double precision,double precision,double precision,double precision) from public, anon;
grant execute on function public.upsert_bus_location(uuid,double precision,double precision,double precision,double precision) to authenticated;
grant execute on function public.is_admin() to anon, authenticated;
revoke all on function public.can_update_bus_location(uuid) from public, anon;
grant execute on function public.can_update_bus_location(uuid) to authenticated;

-- Enable row-level security on all exposed tables.
alter table public.admin_users enable row level security;
alter table public.routes enable row level security;
alter table public.stops enable row level security;
alter table public.route_stops enable row level security;
alter table public.schedules enable row level security;
alter table public.buses enable row level security;
alter table public.bus_assignments enable row level security;
alter table public.bus_locations enable row level security;

-- Public can read published route information; only an admin can manage it.
drop policy if exists routes_public_read on public.routes;
create policy routes_public_read on public.routes for select to anon, authenticated
using (is_active or (select public.is_admin()));
drop policy if exists routes_admin_insert on public.routes;
create policy routes_admin_insert on public.routes for insert to authenticated with check ((select public.is_admin()));
drop policy if exists routes_admin_update on public.routes;
create policy routes_admin_update on public.routes for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists routes_admin_delete on public.routes;
create policy routes_admin_delete on public.routes for delete to authenticated using ((select public.is_admin()));

drop policy if exists stops_public_read on public.stops;
create policy stops_public_read on public.stops for select to anon, authenticated using (true);
drop policy if exists stops_admin_insert on public.stops;
create policy stops_admin_insert on public.stops for insert to authenticated with check ((select public.is_admin()));
drop policy if exists stops_admin_update on public.stops;
create policy stops_admin_update on public.stops for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists stops_admin_delete on public.stops;
create policy stops_admin_delete on public.stops for delete to authenticated using ((select public.is_admin()));

drop policy if exists route_stops_public_read on public.route_stops;
create policy route_stops_public_read on public.route_stops for select to anon, authenticated using (true);
drop policy if exists route_stops_admin_insert on public.route_stops;
create policy route_stops_admin_insert on public.route_stops for insert to authenticated with check ((select public.is_admin()));
drop policy if exists route_stops_admin_update on public.route_stops;
create policy route_stops_admin_update on public.route_stops for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists route_stops_admin_delete on public.route_stops;
create policy route_stops_admin_delete on public.route_stops for delete to authenticated using ((select public.is_admin()));

drop policy if exists schedules_public_read on public.schedules;
create policy schedules_public_read on public.schedules for select to anon, authenticated using (is_active or (select public.is_admin()));
drop policy if exists schedules_admin_insert on public.schedules;
create policy schedules_admin_insert on public.schedules for insert to authenticated with check ((select public.is_admin()));
drop policy if exists schedules_admin_update on public.schedules;
create policy schedules_admin_update on public.schedules for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists schedules_admin_delete on public.schedules;
create policy schedules_admin_delete on public.schedules for delete to authenticated using ((select public.is_admin()));

drop policy if exists buses_public_read on public.buses;
create policy buses_public_read on public.buses for select to anon, authenticated using (is_active or (select public.is_admin()));
drop policy if exists buses_admin_insert on public.buses;
create policy buses_admin_insert on public.buses for insert to authenticated with check ((select public.is_admin()));
drop policy if exists buses_admin_update on public.buses;
create policy buses_admin_update on public.buses for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists buses_admin_delete on public.buses;
create policy buses_admin_delete on public.buses for delete to authenticated using ((select public.is_admin()));

drop policy if exists admin_users_read_self on public.admin_users;
create policy admin_users_read_self on public.admin_users for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists admin_users_admin_all on public.admin_users;
create policy admin_users_admin_all on public.admin_users for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists assignments_admin_all on public.bus_assignments;
create policy assignments_admin_all on public.bus_assignments for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists assignments_read_self on public.bus_assignments;
create policy assignments_read_self on public.bus_assignments for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists bus_locations_public_read on public.bus_locations;
create policy bus_locations_public_read on public.bus_locations for select to anon, authenticated using (true);
drop policy if exists bus_locations_admin_delete on public.bus_locations;
create policy bus_locations_admin_delete on public.bus_locations for delete to authenticated using ((select public.is_admin()));

-- Least-privilege table grants: public reads only; signed-in users can read and write as policies allow.
revoke all on public.routes, public.stops, public.route_stops, public.schedules, public.buses,
  public.bus_locations, public.admin_users, public.bus_assignments from anon, authenticated;
grant select on public.routes, public.stops, public.route_stops, public.schedules, public.buses, public.bus_locations to anon, authenticated;
grant select, insert, update, delete on public.routes, public.stops, public.route_stops,
  public.schedules, public.buses, public.admin_users, public.bus_assignments to authenticated;

-- Seed the initial Coimbatore example route if it does not exist.
-- The distances below are illustrative and must be checked before real deployment.
do $$
declare
  r_id uuid;
  s1 uuid; s2 uuid; s3 uuid; s4 uuid; s5 uuid;
begin
  insert into public.routes(route_code, name, description, is_active)
  values ('THU-GAN', 'Thudiyalur - Gandhipuram', 'Sample Coimbatore route; verify distances before real use.', true)
  on conflict (route_code) do update set name = excluded.name
  returning id into r_id;

  insert into public.stops(stop_code, name) values ('THU','Thudiyalur') on conflict (name) do update set stop_code = excluded.stop_code returning id into s1;
  insert into public.stops(stop_code, name) values ('NGGO','NGGO Colony') on conflict (name) do update set stop_code = excluded.stop_code returning id into s2;
  insert into public.stops(stop_code, name) values ('KAV','Kavundampalayam') on conflict (name) do update set stop_code = excluded.stop_code returning id into s3;
  insert into public.stops(stop_code, name) values ('SAI','Saibaba Colony') on conflict (name) do update set stop_code = excluded.stop_code returning id into s4;
  insert into public.stops(stop_code, name) values ('GAN','Gandhipuram') on conflict (name) do update set stop_code = excluded.stop_code returning id into s5;

  insert into public.route_stops(route_id, stop_id, stop_order, distance_from_previous_km, boarding_min, traffic_factor, extra_delay_min)
  values
    (r_id, s1, 1, 0, 0, 1.25, 2),
    (r_id, s2, 2, 2.5, 2, 1.25, 2),
    (r_id, s3, 3, 3.0, 3, 1.25, 2),
    (r_id, s4, 4, 4.0, 2, 1.25, 2),
    (r_id, s5, 5, 3.5, 1, 1.25, 2)
  on conflict (route_id, stop_id) do update set
    stop_order = excluded.stop_order,
    distance_from_previous_km = excluded.distance_from_previous_km,
    boarding_min = excluded.boarding_min,
    traffic_factor = excluded.traffic_factor,
    extra_delay_min = excluded.extra_delay_min;

  insert into public.schedules(route_id, service_name, departure_time, days_of_week, is_active, notes)
  select r_id, 'Morning service', '09:00', array[0,1,2,3,4,5,6]::smallint[], true,
         'Sample schedule; replace with verified timetable.'
  where not exists (select 1 from public.schedules where route_id = r_id and departure_time = '09:00');

  insert into public.buses(bus_code, route_id, is_active)
  values ('CBT-101', r_id, true)
  on conflict (bus_code) do update set route_id = excluded.route_id;
end;
$$;
