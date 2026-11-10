-- =====================================================================
-- Daily Report NKA - Checklist display bisa diatur TL, Trainer, dan PIC NKA
-- (tambah, ubah, aktif/nonaktif, urutan item). Jalankan SETELAH tahap1c.sql.
-- Aman dijalankan ulang.
-- =====================================================================
drop policy if exists checklist_items_trainer on public.checklist_items;
drop policy if exists checklist_items_atasan on public.checklist_items;
create policy checklist_items_atasan on public.checklist_items for all to authenticated
  using (public.my_role() in ('tl', 'trainer', 'pic'))
  with check (public.my_role() in ('tl', 'trainer', 'pic'));

select 'Checklist display bisa diatur TL, Trainer, PIC' as status;
