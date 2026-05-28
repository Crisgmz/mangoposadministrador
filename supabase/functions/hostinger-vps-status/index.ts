// Edge Function: hostinger-vps-status
//
// Proxy de solo lectura a la API VPS de Hostinger. Mantiene la API key
// `HOSTINGER_API_KEY` server-side (en supabase secrets / .env del stack)
// para que NUNCA viaje al cliente Flutter.
//
// Endpoints Hostinger usados:
//   GET /vps/v1/virtual-machines
//   GET /vps/v1/virtual-machines/{id}/metrics?date_from=...&date_to=...
//
// Shape de la respuesta de /metrics (Hostinger):
//   {
//     cpu_usage:        { unit: '%',       usage: { '<timestamp>': 22.16 } },
//     ram_usage:        { unit: 'bytes',   usage: { '<timestamp>': 4377866240 } },
//     disk_space:       { unit: 'bytes',   usage: { '<timestamp>': 44752138240 } },
//     outgoing_traffic: { unit: 'bytes',   usage: { '<timestamp>': 41291953 } },
//     incoming_traffic: { unit: 'bytes',   usage: { '<timestamp>': 11085805 } },
//     uptime:           { unit: 'seconds', usage: { '<timestamp>': 2417128 } }
//   }
// El "timestamp key" cambia por request — tomamos el último (más reciente).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const HOSTINGER_BASE = 'https://developers.hostinger.com/api';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function pickString(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string') return v.length === 0 ? null : v;
  if (Array.isArray(v)) {
    if (v.length === 0) return null;
    const first = v[0];
    if (typeof first === 'string') return first;
    if (first && typeof first === 'object') {
      const o = first as Record<string, unknown>;
      const candidate = o.address ?? o.ip ?? o.value;
      return typeof candidate === 'string' ? candidate : null;
    }
    return String(first);
  }
  return String(v);
}

function toNum(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'number' ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : null;
}

function lastUsage(metric: unknown): number | null {
  if (!metric || typeof metric !== 'object') return null;
  const usage = (metric as Record<string, unknown>).usage;
  if (!usage || typeof usage !== 'object') return null;
  const entries = Object.entries(usage as Record<string, unknown>);
  if (entries.length === 0) return null;
  entries.sort((a, b) => Number(a[0]) - Number(b[0]));
  const lastVal = entries[entries.length - 1][1];
  return toNum(lastVal);
}

const BYTES_PER_MB = 1024 * 1024;
const BYTES_PER_GB = 1024 * 1024 * 1024;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing authorization header' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? Deno.env.get('API_EXTERNAL_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const hostingerKey = Deno.env.get('HOSTINGER_API_KEY');

    if (!supabaseUrl || !supabaseAnonKey) {
      return json({ error: 'Supabase env vars not configured' }, 500);
    }
    if (!hostingerKey) {
      return json({ error: 'HOSTINGER_API_KEY no configurada en el container.' }, 503);
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: opResult, error: opError } = await supabase.rpc('is_platform_operator');
    if (opError || opResult !== true) {
      return json({ error: 'No autorizado' }, 403);
    }

    const listRes = await fetch(`${HOSTINGER_BASE}/vps/v1/virtual-machines`, {
      headers: { Authorization: `Bearer ${hostingerKey}`, Accept: 'application/json' },
    });
    if (!listRes.ok) {
      const body = await listRes.text();
      return json({
        error: `Hostinger API respondió ${listRes.status}`,
        details: body.slice(0, 500),
      }, 502);
    }

    const listData = await listRes.json();
    const machines: Record<string, unknown>[] = Array.isArray(listData)
      ? listData
      : ((listData as Record<string, unknown>).data as Record<string, unknown>[] ?? []);

    // Rango: últimos 10 minutos (Hostinger toma 1 muestra cada ~5 min).
    const now = new Date();
    const from = new Date(now.getTime() - 10 * 60 * 1000);
    const dateTo = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
    const dateFrom = from.toISOString().replace(/\.\d{3}Z$/, 'Z');

    const instances = await Promise.all(
      machines.map(async (m) => {
        const id = (m.id ?? (m as Record<string, unknown>).virtual_machine_id) as number;

        let metrics: Record<string, number | null> | null = null;
        try {
          const url = `${HOSTINGER_BASE}/vps/v1/virtual-machines/${id}/metrics`
            + `?date_from=${encodeURIComponent(dateFrom)}`
            + `&date_to=${encodeURIComponent(dateTo)}`;
          const mRes = await fetch(url, {
            headers: { Authorization: `Bearer ${hostingerKey}`, Accept: 'application/json' },
          });
          if (mRes.ok) {
            const mData = await mRes.json() as Record<string, unknown>;
            const cpuPct = lastUsage(mData.cpu_usage);
            const ramBytes = lastUsage(mData.ram_usage);
            const diskBytes = lastUsage(mData.disk_space);
            const out = lastUsage(mData.outgoing_traffic) ?? 0;
            const inc = lastUsage(mData.incoming_traffic) ?? 0;
            const uptime = lastUsage(mData.uptime);

            metrics = {
              cpu_percent: cpuPct,
              memory_used_mb: ramBytes !== null ? ramBytes / BYTES_PER_MB : null,
              disk_used_gb: diskBytes !== null ? diskBytes / BYTES_PER_GB : null,
              bandwidth_used_gb: (out + inc) / BYTES_PER_GB,
              uptime_seconds: uptime,
            };
          }
        } catch (_) {}

        const diskMb = toNum(m.disk);
        const diskGb = diskMb !== null ? Math.round(diskMb / 1024) : null;

        const template = m.template as Record<string, unknown> | undefined;
        const templateName = template ? pickString(template.name) : null;

        return {
          id,
          hostname: pickString(m.hostname) ?? pickString(m.name) ?? `vps-${id}`,
          state: pickString(m.state) ?? pickString(m.status) ?? 'unknown',
          ip_address: pickString(m.ipv4) ?? pickString(m.ip_address),
          region: pickString(m.location) ?? pickString(m.region),
          cpu_cores: toNum(m.cpus ?? m.cpu ?? m.cpu_cores),
          memory_mb: toNum(m.memory ?? m.memory_mb),
          disk_gb: diskGb,
          plan: pickString(m.plan),
          template: templateName,
          metrics,
        };
      }),
    );

    return json({ instances });
  } catch (e) {
    return json({ error: `${e}` }, 500);
  }
});
