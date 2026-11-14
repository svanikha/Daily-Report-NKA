// Supabase Edge Function: kirim-notif (Daily Report NKA)
//
// Dipanggil trigger database setiap ada baris baru di tabel "aktivitas",
// dengan body {"event_id": "..."}. Mengirim push Firebase (FCM) ke HP:
//   - TL dan Trainer yang memegang area toko tersebut
//   - semua PIC NKA
// kecuali orang yang melakukan aktivitas itu sendiri.
// Body {"pengingat_id": "..."} (tabel "pengingat") dikirim ke HP PC toko tersebut.
// Push tetap muncul walaupun aplikasi tidak sedang dibuka.
//
// Secret yang dibutuhkan (Edge Functions -> Secrets):
//   FCM_SERVICE_ACCOUNT = seluruh isi file JSON service account Firebase
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY sudah tersedia otomatis.
// Pengaturan function: Verify JWT = OFF (dipanggil dari database).

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type ServiceAccount = { client_email: string; private_key: string; project_id: string };

let cachedToken: { value: string; exp: number } | null = null;

async function googleAccessToken(sa: ServiceAccount) {
  if (cachedToken && cachedToken.exp > Date.now() + 60_000) return cachedToken.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Token Google gagal: ${await res.text()}`);
  const value = (await res.json()).access_token as string;
  cachedToken = { value, exp: Date.now() + 55 * 60_000 };
  return value;
}

// deno-lint-ignore no-explicit-any
type Profil = { id: string; fcm_token: string; notif_channel?: string | null; [k: string]: any };

/** TL & Trainer area toko + semua PIC NKA, selain pelaku aktivitas. */
async function penerima(db: SupabaseClient, storeId: number, pelaku: string | null): Promise<Profil[]> {
  const { data: toko } = await db.from("stores").select("area_id").eq("id", storeId).maybeSingle();
  const areaId = toko?.area_id as number | undefined;
  // select("*"): tetap jalan walau kolom notif_channel belum ada (tahap2g.sql belum dijalankan)
  const { data } = await db
    .from("profiles")
    .select("*")
    .in("role", ["tl", "trainer", "pic"])
    .eq("aktif", true)
    .not("fcm_token", "is", null);
  return ((data ?? []) as Profil[])
    .filter((p) => p.role === "pic" || (areaId != null && p.area_id === areaId))
    .filter((p) => p.id !== pelaku);
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

/**
 * Kirim satu push FCM. Dibuat agar tampil di layar kunci (visibility PUBLIC), sebagai
 * spanduk/heads-up (prioritas maksimum), dan di bilah notifikasi, walau aplikasi ditutup.
 * Channel mengikuti HP penerima: aplikasi baru "nka_penting", aplikasi lama "aktivitas".
 */
async function kirimPush(
  db: SupabaseClient,
  sa: ServiceAccount,
  p: Profil,
  judul: string,
  isi: string,
  data: Record<string, string>,
  tag: string,
): Promise<boolean> {
  const access = await googleAccessToken(sa);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: p.fcm_token,
        notification: { title: judul, body: isi },
        data,
        android: {
          priority: "high",
          ttl: "86400s",
          notification: {
            channel_id: p.notif_channel || "aktivitas",
            tag,
            sound: "default",
            default_sound: true,
            default_vibrate_timings: true,
            default_light_settings: true,
            notification_priority: "PRIORITY_MAX",
            visibility: "PUBLIC",
            ticker: judul,
          },
        },
      },
    }),
  });
  if (!res.ok) {
    const err = await res.text();
    // Token sudah tidak berlaku (aplikasi di-uninstall / logout): hapus agar tidak dicoba lagi
    if (res.status === 404 || err.includes("UNREGISTERED")) {
      await db.from("profiles").update({ fcm_token: null }).eq("id", p.id).eq("fcm_token", p.fcm_token);
    }
  }
  return res.ok;
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  return raw ? (JSON.parse(raw) as ServiceAccount) : null;
}

async function kirimEvent(db: SupabaseClient, eventId: string) {
  const { data: ev } = await db.from("aktivitas").select("*").eq("id", eventId).is("push_pada", null).maybeSingle();
  if (!ev) return json({ event: eventId, dikirim: 0, catatan: "tidak ada atau sudah dikirim" });

  // Tandai dulu agar panggilan ganda tidak mengirim push dua kali
  await db.from("aktivitas").update({ push_pada: new Date().toISOString() }).eq("id", eventId);

  const sa = serviceAccount();
  if (!sa) return json({ event: eventId, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });
  const list = await penerima(db, ev.store_id as number, (ev.oleh as string | null) ?? null);
  if (list.length === 0) return json({ event: eventId, dikirim: 0, catatan: "belum ada HP atasan yang terdaftar" });

  let ok = 0;
  for (const p of list) {
    const terkirim = await kirimPush(db, sa, p, ev.judul, ev.isi, {
      jenis: String(ev.jenis),
      store_id: String(ev.store_id),
      tanggal: String(ev.tanggal),
      event_id: String(ev.id),
    }, String(ev.id));
    if (terkirim) ok++;
  }
  await db.from("aktivitas").update({ push_jumlah: ok }).eq("id", eventId);
  return json({ event: eventId, penerima: list.length, dikirim: ok });
}

/** Pengingat dari TL / Trainer / PIC ke HP PC toko. */
async function kirimPengingat(db: SupabaseClient, id: string) {
  const { data: pg } = await db.from("pengingat").select("*").eq("id", id).is("push_pada", null).maybeSingle();
  if (!pg) return json({ pengingat: id, dikirim: 0, catatan: "tidak ada atau sudah dikirim" });
  await db.from("pengingat").update({ push_pada: new Date().toISOString() }).eq("id", id);

  const sa = serviceAccount();
  if (!sa) return json({ pengingat: id, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });

  const { data: pc } = await db.from("profiles").select("*").eq("id", pg.pc_id).maybeSingle();
  if (!pc?.fcm_token) {
    await db.from("pengingat").update({ push_ok: false }).eq("id", id);
    return json({ pengingat: id, dikirim: 0, catatan: "HP PC belum terdaftar" });
  }
  const { data: dari } = await db.from("profiles").select("*").eq("id", pg.dari).maybeSingle();
  const peran = dari?.jabatan ?? (dari?.role === "tl" ? "TL" : dari?.role === "trainer" ? "Trainer" : "PIC NKA");
  const judul = `Pengingat dari ${dari?.nama ?? "atasan"} (${peran})`;

  const ok = await kirimPush(db, sa, pc as Profil, judul, pg.pesan, {
    jenis: "pengingat",
    store_id: String(pg.store_id),
    pengingat_id: String(pg.id),
  }, String(pg.id));
  await db.from("pengingat").update({ push_ok: ok }).eq("id", id);
  return json({ pengingat: id, dikirim: ok ? 1 : 0 });
}

const labelPeran = (role?: string) =>
  role === "tl" ? "TL" : role === "trainer" ? "Trainer" : role === "pic" ? "PIC NKA" : "PC";

/** Balasan "Siap 👍" PC: hanya dikirim ke atasan yang mengirim pengingat. */
async function kirimRespon(db: SupabaseClient, id: string) {
  const sa = serviceAccount();
  if (!sa) return json({ respon: id, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });
  const { data: pg } = await db.from("pengingat").select("*").eq("id", id).maybeSingle();
  if (!pg?.dari) return json({ respon: id, dikirim: 0, catatan: "pengingat tidak ada" });
  const { data: atasan } = await db.from("profiles").select("*").eq("id", pg.dari).maybeSingle();
  if (!atasan?.fcm_token) return json({ respon: id, dikirim: 0, catatan: "HP pengirim belum terdaftar" });
  const { data: pc } = await db.from("profiles").select("nama").eq("id", pg.pc_id).maybeSingle();
  const { data: toko } = await db.from("stores").select("nama").eq("id", pg.store_id).maybeSingle();
  const siap = !pg.respon || pg.respon === "Siap";
  const ok = await kirimPush(db, sa, atasan as Profil,
    siap ? `${pc?.nama ?? "PC"}: Siap 👍` : `💬 ${pc?.nama ?? "PC"} membalas: ${pg.respon}`,
    `${toko?.nama ?? ""} · pesanmu: ${pg.pesan}`,
    { jenis: "respon_pengingat", store_id: String(pg.store_id), pengingat_id: String(pg.id) }, `respon-${pg.id}`);
  return json({ respon: id, dikirim: ok ? 1 : 0 });
}

/** Pesan pribadi antar atasan (TL, Trainer, PIC NKA). */
async function kirimPesan(db: SupabaseClient, id: string) {
  const sa = serviceAccount();
  if (!sa) return json({ pesan: id, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });
  const { data: m } = await db.from("pesan_atasan").select("*").eq("id", id).maybeSingle();
  if (!m) return json({ pesan: id, dikirim: 0, catatan: "pesan tidak ada" });
  const { data: ke } = await db.from("profiles").select("*").eq("id", m.ke).maybeSingle();
  if (!ke?.fcm_token) return json({ pesan: id, dikirim: 0, catatan: "HP penerima belum terdaftar" });
  const { data: dari } = await db.from("profiles").select("*").eq("id", m.dari).maybeSingle();
  const ok = await kirimPush(db, sa, ke as Profil, `💬 ${dari?.nama ?? "Atasan"} (${dari?.jabatan ?? labelPeran(dari?.role)})`, m.isi,
    { jenis: "pesan", dari: String(m.dari), pesan_id: String(m.id) }, `pesan-${m.dari}`);
  return json({ pesan: id, dikirim: ok ? 1 : 0 });
}

type Objek = { name: string; size: number };

/**
 * Pembersihan penyimpanan (dipanggil cron harian 02.00 WIB atau tombol PIC):
 * foto bukti > N hari, APK lama (simpan 5 terbaru per saluran), dan jika masih >= 80% kuota,
 * foto tertua dihapus sampai < 70% (foto 7 hari terakhir tetap disimpan).
 */
async function bersihkan(db: SupabaseClient, token: string, pemicu: string) {
  const { data: set } = await db.from("pengaturan").select("*");
  const p: Record<string, string> = Object.fromEntries((set ?? []).map((r) => [r.kunci, r.nilai]));
  if (!token || token !== p.bersih_token) return json({ error: "kunci pembersihan salah" }, 403);
  const kuota = Number(p.kuota_storage_bytes || 1073741824);
  const umur = Number(p.umur_foto_hari || 30);
  const batas = Number(p.batas_persen || 80);
  const target = Number(p.target_persen || 70);
  const simpanApk = Number(p.simpan_apk || 5);

  const ukur = async () => {
    const { data } = await db.rpc("ukuran_storage");
    return Number(data?.total ?? 0);
  };
  const sebelum = await ukur();
  let foto = 0, apk = 0, bebas = 0;
  const catatan: string[] = [];

  const hapus = async (bucket: string, rows: Objek[]) => {
    for (let i = 0; i < rows.length; i += 100) {
      const chunk = rows.slice(i, i + 100);
      const names = chunk.map((r) => r.name);
      const { error } = await db.storage.from(bucket).remove(names);
      if (error) {
        catatan.push(`${bucket}: ${error.message}`);
        continue;
      }
      bebas += chunk.reduce((a, r) => a + Number(r.size || 0), 0);
      if (bucket === "bukti") {
        await db.from("photos").delete().in("path", names);
        foto += names.length;
      } else {
        apk += names.length;
      }
    }
  };

  // 1. Foto bukti lebih tua dari N hari
  const sebelumTgl = new Date(Date.now() - umur * 86400000).toISOString();
  for (let n = 0; n < 30; n++) {
    const { data } = await db.rpc("objek_storage", { p_bucket: "bukti", p_sebelum: sebelumTgl, p_limit: 1000 });
    const rows = (data ?? []) as Objek[];
    if (rows.length === 0) break;
    await hapus("bukti", rows);
    if (rows.length < 1000) break;
  }

  // 2. APK lama
  const { data: apkLama } = await db.rpc("apk_lama", { p_simpan: simpanApk });
  if ((apkLama ?? []).length > 0) await hapus("apk", apkLama as Objek[]);

  // 3. Masih >= batas % kuota: hapus foto tertua (simpan 7 hari terakhir) sampai < target %
  let sekarang = await ukur();
  if (sekarang >= (kuota * batas) / 100) {
    const tujuh = new Date(Date.now() - 7 * 86400000).toISOString();
    for (let n = 0; n < 50 && sekarang > (kuota * target) / 100; n++) {
      const { data } = await db.rpc("objek_storage", { p_bucket: "bukti", p_sebelum: tujuh, p_limit: 200 });
      const rows = (data ?? []) as Objek[];
      if (rows.length === 0) {
        catatan.push("masih di atas batas, tetapi tinggal foto 7 hari terakhir");
        break;
      }
      await hapus("bukti", rows);
      sekarang = await ukur();
    }
  }

  const sesudah = await ukur();
  await db.from("storage_bersih_log").insert({
    pemicu,
    foto_dihapus: foto,
    apk_dihapus: apk,
    bytes_dibebaskan: bebas,
    ukuran_sebelum: sebelum,
    ukuran_sesudah: sesudah,
    catatan: catatan.join("; ") || null,
  });
  return json({ foto, apk, bebas, sebelum, sesudah, kuota });
}

/** Push percobaan ke HP sendiri (tombol "Tes notifikasi"). */
async function kirimTes(db: SupabaseClient, profileId: string) {
  const sa = serviceAccount();
  if (!sa) return json({ tes: profileId, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });
  const { data: p } = await db.from("profiles").select("*").eq("id", profileId).maybeSingle();
  if (!p?.fcm_token) return json({ tes: profileId, dikirim: 0, catatan: "HP belum terdaftar" });
  const jam = new Date().toLocaleTimeString("id-ID", { timeZone: "Asia/Jakarta", hour: "2-digit", minute: "2-digit" });
  const ok = await kirimPush(db, sa, p as Profil, "Tes notifikasi Daily Report NKA",
    `Notifikasi HP ${p.nama ?? ""} sudah aktif (${jam} WIB). Cek juga di layar kunci.`,
    { jenis: "tes" }, `tes-${profileId}`);
  return json({ tes: profileId, dikirim: ok ? 1 : 0 });
}

Deno.serve(async (req) => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  try {
    if (body?.bersihkan) return await bersihkan(db, String(body.bersihkan), String(body.pemicu ?? "manual"));
    if (body?.tes_profile) return await kirimTes(db, String(body.tes_profile));
    if (body?.respon_pengingat) return await kirimRespon(db, String(body.respon_pengingat));
    if (body?.pesan_id) return await kirimPesan(db, String(body.pesan_id));
    if (body?.pengingat_id) return await kirimPengingat(db, String(body.pengingat_id));
    if (!body?.event_id) return json({ error: "event_id wajib" }, 400);
    return await kirimEvent(db, String(body.event_id));
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
