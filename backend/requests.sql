create table if not exists public.quote_requests (
 id uuid primary key default gen_random_uuid(),
 customer jsonb not null,
 items jsonb not null,
 created_at timestamptz not null default now(),
 status text not null default 'new' check(status in ('new','contacted','closed'))
);
alter table public.quote_requests enable row level security;
grant select,update on public.quote_requests to authenticated;
create policy request_editor_read on public.quote_requests for select to authenticated using(exists(select 1 from public.catalog_editors where user_id=auth.uid()));
create policy request_editor_update on public.quote_requests for update to authenticated using(exists(select 1 from public.catalog_editors where user_id=auth.uid())) with check(exists(select 1 from public.catalog_editors where user_id=auth.uid()));
create or replace function public.submit_quote(request_id uuid, customer_data jsonb, requested_items jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare entry jsonb; product_record public.products%rowtype; snapshot jsonb := '[]'::jsonb; amount integer; email_value text; clean_customer jsonb;
begin
 if request_id is null or jsonb_typeof(customer_data) <> 'object' or jsonb_typeof(requested_items) <> 'array' then raise exception 'Invalid request'; end if;
 if length(customer_data::text)>6000 or jsonb_array_length(requested_items) not between 1 and 100 then raise exception 'Invalid request size'; end if;
 email_value := lower(trim(customer_data->>'email'));
 if email_value is null or length(email_value)>254 or email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email'; end if;
 if coalesce(length(trim(customer_data->>'company')),0) not between 1 and 160 or coalesce(length(trim(customer_data->>'name')),0) not between 1 and 160 or coalesce(length(trim(customer_data->>'phone')),0) not between 3 and 60 or coalesce(length(trim(customer_data->>'address')),0) not between 5 and 1000 then raise exception 'Fill in company, contact and delivery address'; end if;
 if coalesce(length(customer_data->>'notes'),0)>2000 then raise exception 'Notes too long'; end if;
 clean_customer := jsonb_build_object('company',trim(customer_data->>'company'),'name',trim(customer_data->>'name'),'email',email_value,'phone',trim(customer_data->>'phone'),'address',trim(customer_data->>'address'),'notes',coalesce(customer_data->>'notes',''));
 perform pg_advisory_xact_lock(hashtext(email_value));
 if exists(select 1 from public.quote_requests where id=request_id) then
   if exists(select 1 from public.quote_requests where id=request_id and customer=clean_customer) then return request_id; end if;
   raise exception 'Request identifier already used';
 end if;
 if (select count(*) from public.quote_requests where customer->>'email'=email_value and created_at>now()-interval '1 hour')>=5 then raise exception 'Too many requests. Contact info@sabafood.se'; end if;
 for entry in select value from jsonb_array_elements(requested_items) loop
   if coalesce(entry->>'quantity','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid quantity'; end if;
   amount := (entry->>'quantity')::integer;
   if amount not between 1 and 999 then raise exception 'Invalid quantity'; end if;
   select * into product_record from public.products where id=(entry->>'id')::uuid and published=true;
   if not found then raise exception 'Product unavailable. Reload catalog'; end if;
   if exists(select 1 from jsonb_array_elements(snapshot) x where x->>'id'=product_record.id::text) then raise exception 'Duplicate product'; end if;
   snapshot := snapshot || jsonb_build_array(jsonb_build_object('id',product_record.id,'name',product_record.name,'brand',product_record.brand,'weight',product_record.weight,'units',product_record.units,'quantity',amount));
 end loop;
 insert into public.quote_requests(id,customer,items) values(request_id,clean_customer,snapshot);
 return request_id;
end $$;
revoke all on function public.submit_quote(uuid,jsonb,jsonb) from public;
grant execute on function public.submit_quote(uuid,jsonb,jsonb) to anon,authenticated;
alter table public.quote_requests add constraint nonempty_quote_items check(jsonb_typeof(items)='array' and jsonb_array_length(items) between 1 and 100);
alter table public.quote_requests add constraint valid_quote_email check(customer->>'email' ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$');
