// Supabase Edge Function: kirim-notif (Daily Report NKA)
//
// Dipanggil trigger database setiap ada baris baru di tabel "aktivitas",
// dengan body {"event_id": "..."}. Mengirim push Firebase (FCM) ke HP:
//   - TL dan Trainer yang memegang area toko tersebut
//   - semua PIC NKA
// kecuali orang yang melakukan aktivitas itu sendiri.
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

type Penerima = { id: string; fcm_token: string };

/** TL & Trainer area toko + semua PIC NKA, selain pelaku aktivitas. */
async function penerima(db: SupabaseClient, storeId: number, pelaku: string | null): Promise<Penerima[]> {
  const { data: toko } = await db.from("stores").select("area_id").eq("id", storeId).maybeSingle();
  const areaId = toko?.area_id as number | undefined;
  const { data } = await db
    .from("profiles")
    .select("id, role, area_id, fcm_token")
    .in("role", ["tl", "trainer", "pic"])
    .eq("aktif", true)
    .not("fcm_token", "is", null);
  return (data ?? [])
    .filter((p) => p.role === "pic" || (areaId != null && p.area_id === areaId))
    .filter((p) => p.id !== pelaku)
    .map((p) => ({ id: p.id as string, fcm_token: p.fcm_token as string }));
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

async function kirimEvent(db: SupabaseClient, eventId: string) {
  const { data: ev } = await db.from("aktivitas").select("*").eq("id", eventId).is("push_pada", null).maybeSingle();
  if (!ev) return json({ event: eventId, dikirim: 0, catatan: "tidak ada atau sudah dikirim" });

  // Tandai dulu agar panggilan ganda tidak mengirim push dua kali
  await db.from("aktivitas").update({ push_pada: new Date().toISOString() }).eq("id", eventId);

  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) return json({ event: eventId, dikirim: 0, catatan: "FCM_SERVICE_ACCOUNT belum diisi" });
  const sa = JSON.parse(saRaw) as ServiceAccount;
  const list = await penerima(db, ev.store_id as number, (ev.oleh as string | null) ?? null);
  if (list.length === 0) return json({ event: eventId, dikirim: 0, catatan: "belum ada HP atasan yang terdaftar" });

  const access = await googleAccessToken(sa);
  let ok = 0;
  for (const p of list) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: p.fcm_token,
          notification: { title: ev.judul, body: ev.isi },
          data: { jenis: String(ev.jenis), store_id: String(ev.store_id), tanggal: String(ev.tanggal), event_id: String(ev.id) },
          android: {
            priority: "high",
            notification: { channel_id: "aktivitas", sound: "default", tag: String(ev.id) },
          },
        },
      }),
    });
    if (res.ok) {
      ok++;
    } else {
      const err = await res.text();
      // Token sudah tidak berlaku (aplikasi di-uninstall / logout): hapus agar tidak dicoba lagi
      if (res.status === 404 || err.includes("UNREGISTERED")) {
        await db.from("profiles").update({ fcm_token: null }).eq("id", p.id).eq("fcm_token", p.fcm_token);
      }
    }
  }
  await db.from("aktivitas").update({ push_jumlah: ok }).eq("id", eventId);
  return json({ event: eventId, penerima: list.length, dikirim: ok });
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
    if (!body?.event_id) return json({ error: "event_id wajib" }, 400);
    return await kirimEvent(db, String(body.event_id));
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
