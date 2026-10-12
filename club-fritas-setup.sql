-- CLUB FRITAS: solicitudes pendientes y aprobación exclusiva del administrador.
-- Ejecutar en Supabase SQL Editor como propietario del proyecto.
create table if not exists public.club_requests (
 id uuid primary key default gen_random_uuid(),
 phone text not null check (phone ~ '^\\+569[0-9]{8}$'),
 customer_name text not null check (char_length(trim(customer_name)) between 2 and 100),
 marketing_opt_in boolean not null default false,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid
);
create unique index if not exists club_requests_pending_phone on public.club_requests(phone) where status='pending';
create index if not exists club_requests_status_created on public.club_requests(status,created_at desc);
alter table public.club_requests enable row level security;
revoke all on public.club_requests from anon, authenticated;
grant select,update on public.club_requests to authenticated;
drop policy if exists club_requests_admin_select on public.club_requests;
create policy club_requests_admin_select on public.club_requests for select to authenticated using (public.has_staff_role('admin'));
drop policy if exists club_requests_admin_update on public.club_requests;
create policy club_requests_admin_update on public.club_requests for update to authenticated using (public.has_staff_role('admin')) with check (public.has_staff_role('admin'));

-- Clientes existentes: guardar autorización de marketing y fecha.
alter table public.club_customers add column if not exists marketing_opt_in boolean not null default false;
alter table public.club_customers add column if not exists marketing_consent_at timestamptz;
alter table public.club_customers add column if not exists approved_at timestamptz;
alter table public.club_customers add column if not exists approved_by uuid;
revoke all on public.club_customers from anon, authenticated;

-- La solicitud NO verifica el número: administración debe comprobar el remitente en WhatsApp.
create or replace function public.club_request_join(p_phone text,p_name text,p_marketing_opt_in boolean default false)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_phone text; v_name text;
begin
 v_phone := trim(p_phone); v_name := trim(p_name);
 if v_phone !~ '^\\+569[0-9]{8}$' or char_length(v_name) not between 2 and 100 then
   raise exception 'Datos inválidos';
 end if;
 if exists (select 1 from public.club_customers where phone=v_phone) then return 'already_member'; end if;
 if exists (select 1 from public.club_requests where phone=v_phone and status='pending') then return 'already_pending'; end if;
 insert into public.club_requests(phone,customer_name,marketing_opt_in) values(v_phone,v_name,coalesce(p_marketing_opt_in,false));
 return 'pending';
end $$;
revoke all on function public.club_request_join(text,text,boolean) from public;
grant execute on function public.club_request_join(text,text,boolean) to anon,authenticated;

create or replace function public.club_review_request(p_request_id uuid,p_approve boolean)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.club_requests%rowtype;
begin
 if auth.uid() is null or not public.has_staff_role('admin') then raise exception 'Solo administración'; end if;
 select * into v from public.club_requests where id=p_request_id and status='pending' for update;
 if not found then raise exception 'Solicitud no disponible'; end if;
 if p_approve then
   insert into public.club_customers(phone,customer_name,marketing_opt_in,marketing_consent_at,approved_at,approved_by)
   values(v.phone,v.customer_name,v.marketing_opt_in,case when v.marketing_opt_in then v.created_at else null end,now(),auth.uid())
   on conflict(phone) do update set customer_name=excluded.customer_name,
     marketing_opt_in=excluded.marketing_opt_in,
     marketing_consent_at=excluded.marketing_consent_at,
     approved_at=now(),approved_by=auth.uid();
 end if;
 update public.club_requests set status=case when p_approve then 'approved' else 'rejected' end,
 reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
 return case when p_approve then 'approved' else 'rejected' end;
end $$;
revoke all on function public.club_review_request(uuid,boolean) from public;
grant execute on function public.club_review_request(uuid,boolean) to authenticated;
