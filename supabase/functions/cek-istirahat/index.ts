// Supabase Edge Function: cek-istirahat (alamat terpasang: rapid-function)
//
// Dua tugas:
// 1. Dipanggil cron setiap 5 menit (body {}): mencari sesi istirahat yang
//    sudah melewati durasi pilihannya (1 jam / 3 jam), lalu mengirim push ke HP admin.
// 2. Dipanggil trigger database dengan body {"event_id": "..."}: mengirim push
//    "Pesan Masuk" (penjualan, istirahat, leasing) ke HP admin.
//
// Secret yang dibutuhkan (Edge Functions -> Secrets):
//   FCM_SERVICE_ACCOUNT = isi file JSON service account Firebase
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY sudah tersedia otomatis.
// Pengaturan function: Enforce JWT Verification = OFF.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";


type ServiceAccount = { client_email: string; private_key: string; project_id: string };

async function googleAccessToken(sa: ServiceAccount) {
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
  return (await res.json()).access_token as string;
}

function jamWib(iso: string) {
  return new Date(iso).toLocaleTimeString("id-ID", { timeZone: "Asia/Jakarta", hour: "2-digit", minute: "2-digit" });
}

/** Token HP penerima: semua admin + admin support di toko PC tersebut. */
async function adminTokens(db: SupabaseClient, storeId: number | null) {
  const { data } = await db
    .from("profiles")
    .select("fcm_token, role, store_id")
    .in("role", ["admin", "support"])
    .eq("aktif", true)
    .not("fcm_token", "is", null);
  return (data ?? [])
    .filter((p) => p.role === "admin" || (storeId != null && p.store_id === storeId))
    .map((p) => p.fcm_token as string)
    .filter(Boolean);
}

async function storeOfPc(db: SupabaseClient, pcId: string | null) {
  if (!pcId) return null;
  const { data } = await db.from("profiles").select("store_id").eq("id", pcId).maybeSingle();
  return (data?.store_id as number | null) ?? null;
}

/** Mengirim push ke HP admin & support toko terkait. Mengembalikan jumlah yang berhasil. */
async function kirimPush(
  db: SupabaseClient,
  title: string,
  body: string,
  channel: string,
  storeId: number | null,
  data: Record<string, string> = {},
) {
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  const tokens = await adminTokens(db, storeId);
  if (!saRaw || tokens.length === 0) return 0;
  const sa = JSON.parse(saRaw) as ServiceAccount;
  const access = await googleAccessToken(sa);
  let ok = 0;
  for (const token of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: "high", notification: { channel_id: channel } },
        },
      }),
    });
    if (res.ok) ok++;
  }
  return ok;
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

async function kirimEvent(db: SupabaseClient, eventId: string) {
  const { data: ev } = await db.from("admin_events").select("*").eq("id", eventId).is("push_pada", null).maybeSingle();
  if (!ev) return json({ event: eventId, dikirim: 0, catatan: "tidak ada atau sudah dikirim" });
  const storeId = await storeOfPc(db, ev.pc_id);
  const dikirim = await kirimPush(db, ev.judul, ev.isi, "pesan_masuk", storeId, { jenis: ev.jenis, pc_id: ev.pc_id ?? "" });
  await db.from("admin_events").update({ push_pada: new Date().toISOString() }).eq("id", eventId);
  return json({ event: eventId, dikirim });
}

async function cekIstirahat(db: SupabaseClient) {
  // Tutup dulu sesi yang lupa diakhiri sampai 23.00 WIB
  await db.rpc("tutup_istirahat_otomatis");

  // Istirahat yang sudah melewati durasi pilihannya (1 jam atau 3 jam)
  const { data: lewat, error } = await db.rpc("istirahat_lewat");
  if (error) return json({ error: error.message }, 500);
  if (!lewat || lewat.length === 0) return json({ dikirim: 0 });

  let dikirim = 0;
  for (const b of lewat as { id: string; mulai: string; durasi_menit: number; nama: string; toko: string; store_id: number | null }[]) {
    const dur = b.durasi_menit === 60 ? "1 jam" : "3 jam";
    dikirim += await kirimPush(
      db,
      `Istirahat lebih dari ${dur}`,
      `${b.nama} (${b.toko}) mulai istirahat ${dur} pukul ${jamWib(b.mulai)} WIB dan belum kembali ke toko.`,
      "admin_alert",
      b.store_id ?? null,
    );
  }

  // Tandai sudah diperingatkan agar tidak dikirim berulang
  await db.from("breaks").update({ peringatan_admin_pada: new Date().toISOString() }).in("id", (lewat as { id: string }[]).map((b) => b.id));
  return json({ sesi: lewat.length, dikirim });
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
    if (body?.event_id) return await kirimEvent(db, String(body.event_id));
    return await cekIstirahat(db);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
