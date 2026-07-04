package main

import (
	"encoding/json"
	"log"
	"net/http"
)

// Stats is the aggregated usage snapshot returned to the admin dashboard.
type Stats struct {
	TotalUsers int          `json:"total_users"`
	NewToday   int          `json:"new_today"`
	New7d      int          `json:"new_7d"`
	New30d     int          `json:"new_30d"`
	ActiveDAU  int          `json:"active_dau"`
	ActiveWAU  int          `json:"active_wau"`
	ActiveMAU  int          `json:"active_mau"`
	Servers    int          `json:"servers"`
	Daily      []DailyPoint `json:"daily"`
}

// DailyPoint is a single day in the registrations time-series.
type DailyPoint struct {
	Date  string `json:"date"`
	Count int    `json:"count"`
}

// authorizeAdmin checks the admin token supplied either as a Bearer header or a
// `token` query parameter (so the dashboard can fetch from the browser).
func authorizeAdmin(r *http.Request) bool {
	expected := getEnv("ADMIN_TOKEN", "")
	if expected == "" {
		return false
	}
	if r.Header.Get("Authorization") == "Bearer "+expected {
		return true
	}
	if r.URL.Query().Get("token") == expected {
		return true
	}
	return false
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	if !authorizeAdmin(r) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var s Stats

	if err := DB.QueryRow(`SELECT COUNT(*) FROM vpn_users`).Scan(&s.TotalUsers); err != nil {
		log.Printf("stats total error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	err := DB.QueryRow(`
		SELECT
			COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day'),
			COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days'),
			COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days')
		FROM vpn_users`).Scan(&s.NewToday, &s.New7d, &s.New30d)
	if err != nil {
		log.Printf("stats new error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	err = DB.QueryRow(`
		SELECT
			COUNT(*) FILTER (WHERE last_connected_at > NOW() - INTERVAL '1 day'),
			COUNT(*) FILTER (WHERE last_connected_at > NOW() - INTERVAL '7 days'),
			COUNT(*) FILTER (WHERE last_connected_at > NOW() - INTERVAL '30 days')
		FROM vpn_users`).Scan(&s.ActiveDAU, &s.ActiveWAU, &s.ActiveMAU)
	if err != nil {
		log.Printf("stats active error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	_ = DB.QueryRow(`SELECT COUNT(*) FROM servers WHERE enabled = TRUE`).Scan(&s.Servers)

	rows, err := DB.Query(`
		SELECT to_char(DATE(created_at), 'YYYY-MM-DD') AS day, COUNT(*)
		FROM vpn_users
		WHERE created_at > NOW() - INTERVAL '30 days'
		GROUP BY day
		ORDER BY day ASC`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p DailyPoint
			if err := rows.Scan(&p.Date, &p.Count); err == nil {
				s.Daily = append(s.Daily, p)
			}
		}
	}
	if s.Daily == nil {
		s.Daily = []DailyPoint{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(s)
}

// handleAdmin serves the single-page admin dashboard. The page itself is public;
// data is only fetched after the admin enters a valid token.
func handleAdmin(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Write([]byte(adminPage))
}

// adminPage is the embedded dashboard HTML. It stores the token in localStorage
// and polls /api/stats.
const adminPage = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex, nofollow" />
<title>Barys VPN — Admin</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<style>
  :root { --bg:#0b0f17; --card:#151b26; --line:#232c3b; --text:#e7ecf3; --muted:#8a97ab; --accent:#4f8cff; --green:#33d69f; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif; background:var(--bg); color:var(--text); }
  header { padding:20px 24px; border-bottom:1px solid var(--line); display:flex; align-items:center; justify-content:space-between; }
  header h1 { font-size:18px; margin:0; }
  header .sub { color:var(--muted); font-size:13px; margin-top:2px; }
  .wrap { padding:24px; max-width:1100px; margin:0 auto; }
  .login { max-width:360px; margin:80px auto; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:28px; }
  .login h2 { margin:0 0 16px; font-size:16px; }
  input { width:100%; padding:12px 14px; border-radius:10px; border:1px solid var(--line); background:#0e1421; color:var(--text); font-size:14px; }
  button { margin-top:14px; width:100%; padding:12px; border:0; border-radius:10px; background:var(--accent); color:#fff; font-size:14px; font-weight:600; cursor:pointer; }
  button.secondary { background:transparent; border:1px solid var(--line); color:var(--muted); width:auto; padding:8px 14px; margin:0; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:16px; margin-bottom:24px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px; }
  .card .label { color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.4px; }
  .card .value { font-size:30px; font-weight:700; margin-top:8px; }
  .card .value.green { color:var(--green); }
  .section { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px; margin-bottom:24px; }
  .section h3 { margin:0 0 14px; font-size:14px; color:var(--muted); font-weight:600; }
  .row { display:flex; align-items:center; justify-content:space-between; gap:12px; }
  .muted { color:var(--muted); font-size:12px; }
  .err { color:#ff6b6b; font-size:13px; margin-top:10px; min-height:16px; }
  .hidden { display:none; }
</style>
</head>
<body>
<div id="loginView" class="login">
  <h2>Barys VPN — панель</h2>
  <input id="token" type="password" placeholder="Admin token" autocomplete="off" />
  <button onclick="login()">Войти</button>
  <div class="err" id="loginErr"></div>
</div>

<div id="dashView" class="hidden">
  <header>
    <div>
      <h1>Barys VPN — статистика</h1>
      <div class="sub" id="updated">—</div>
    </div>
    <button class="secondary" onclick="logout()">Выйти</button>
  </header>
  <div class="wrap">
    <div class="grid">
      <div class="card"><div class="label">Всего устройств</div><div class="value" id="m_total">—</div></div>
      <div class="card"><div class="label">Активны сегодня</div><div class="value green" id="m_dau">—</div></div>
      <div class="card"><div class="label">Активны за 7 дней</div><div class="value green" id="m_wau">—</div></div>
      <div class="card"><div class="label">Активны за 30 дней</div><div class="value green" id="m_mau">—</div></div>
    </div>
    <div class="grid">
      <div class="card"><div class="label">Новые сегодня</div><div class="value" id="m_new1">—</div></div>
      <div class="card"><div class="label">Новые за 7 дней</div><div class="value" id="m_new7">—</div></div>
      <div class="card"><div class="label">Новые за 30 дней</div><div class="value" id="m_new30">—</div></div>
      <div class="card"><div class="label">Серверов онлайн</div><div class="value" id="m_srv">—</div></div>
    </div>
    <div class="section">
      <div class="row"><h3>Регистрации по дням (30 дней)</h3><span class="muted" id="autoNote">обновление каждые 30 сек</span></div>
      <canvas id="chart" height="90"></canvas>
    </div>
  </div>
</div>

<script>
var TOKEN = localStorage.getItem('barys_admin_token') || '';
var chart = null;

function apiBase() {
  // Page may be served under a reverse-proxy prefix (e.g. /vpn/admin).
  // Resolve "api/stats" relative to the current path.
  return location.pathname.replace(/\/admin\/?$/, '') + '/api/stats';
}

async function fetchStats() {
  var res = await fetch(apiBase(), { headers: { 'Authorization': 'Bearer ' + TOKEN } });
  if (res.status === 401) throw new Error('unauthorized');
  if (!res.ok) throw new Error('http ' + res.status);
  return res.json();
}

function set(id, v) { document.getElementById(id).textContent = v; }

function render(s) {
  set('m_total', s.total_users);
  set('m_dau', s.active_dau);
  set('m_wau', s.active_wau);
  set('m_mau', s.active_mau);
  set('m_new1', s.new_today);
  set('m_new7', s.new_7d);
  set('m_new30', s.new_30d);
  set('m_srv', s.servers);
  set('updated', 'Обновлено: ' + new Date().toLocaleString());

  var labels = s.daily.map(function(d){ return d.date.slice(5); });
  var data = s.daily.map(function(d){ return d.count; });
  if (chart) { chart.data.labels = labels; chart.data.datasets[0].data = data; chart.update(); return; }
  var ctx = document.getElementById('chart').getContext('2d');
  chart = new Chart(ctx, {
    type: 'line',
    data: { labels: labels, datasets: [{ label: 'Новые устройства', data: data, borderColor: '#4f8cff', backgroundColor: 'rgba(79,140,255,.15)', fill: true, tension: .3, pointRadius: 2 }] },
    options: { plugins: { legend: { labels: { color: '#8a97ab' } } }, scales: { x: { ticks: { color: '#8a97ab' }, grid: { color: '#232c3b' } }, y: { ticks: { color: '#8a97ab' }, grid: { color: '#232c3b' }, beginAtZero: true } } }
  });
}

async function refresh() {
  try { render(await fetchStats()); }
  catch (e) { if (String(e.message) === 'unauthorized') { logout(); } }
}

function showDash() {
  document.getElementById('loginView').classList.add('hidden');
  document.getElementById('dashView').classList.remove('hidden');
  refresh();
  setInterval(refresh, 30000);
}

async function login() {
  TOKEN = document.getElementById('token').value.trim();
  try {
    await fetchStats();
    localStorage.setItem('barys_admin_token', TOKEN);
    showDash();
  } catch (e) {
    document.getElementById('loginErr').textContent = 'Неверный токен или ошибка сервера';
  }
}

function logout() {
  localStorage.removeItem('barys_admin_token');
  TOKEN = '';
  location.reload();
}

if (TOKEN) { showDash(); }
</script>
</body>
</html>`
