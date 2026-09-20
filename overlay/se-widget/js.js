// BadScore — Custom Widget StreamElements : onglet JS.
// Port de overlay/index.html (lecture publique Supabase via REST, clé anon).
// Sonde toutes les 2 s : score affiché ≤ 2 s après chaque point. Choix du
// match : le plus récent ACTIF du canal ; sinon le plus récent (final reste
// affiché). Aucune manipulation, aucune authentification sensible.
window.addEventListener("onWidgetLoad", function (obj) {
  const f = obj.detail.fieldData;
  const SUPABASE_URL = "https://bzdbnptnubkkagmmxhyi.supabase.co";
  const REST = SUPABASE_URL + "/rest/v1";
  // Clé anon publique (RLS SELECT) — identique à l'overlay GitHub Pages.
  const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ6ZGJucHRudWJra2FnbW14aHlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk3Nzk5MDAsImV4cCI6MjEwNTM1NTkwMH0._g_LV07W42GlOijx-XptJBJwBrfSgbcAm8StEWxqge0";
  const HEADERS = { "apikey": ANON_KEY, "Authorization": "Bearer " + ANON_KEY };

  const CHANNEL = (f.channel || "marc").replace(/[^A-Za-z0-9_-]/g, "");
  const NAME1 = f.name1 || "MOI";
  const NAME2 = f.name2 || "LUI";
  const SCALE = parseFloat(f.scale || 1);
  const SHOW_PANELS = f.bg !== false;

  document.getElementById("n1").textContent = NAME1;
  document.getElementById("n2").textContent = NAME2;
  if (!SHOW_PANELS) {
    const bug = document.getElementById("bug");
    bug.style.background = "transparent";
    bug.style.borderColor = "transparent";
    bug.style.boxShadow = "none";
    document.querySelector(".sep").style.background = "rgba(255, 255, 255, 0.25)";
    document.querySelectorAll(".name, .pts, .setlab").forEach((el) => {
      el.style.textShadow = "0 2px 8px rgba(0, 0, 0, 0.8)";
    });
  }
  if (SCALE !== 1) document.getElementById("wrap").style.setProperty("--scale", SCALE);

  function pips(el, won, setsToWin) {
    const total = Math.max(2, setsToWin);
    el.innerHTML = "";
    for (let i = 0; i < total; i++) {
      const p = document.createElement("div");
      p.className = "pip" + (won > i ? " won" : "");
      p.dataset.won = won > i ? "1" : "0";
      el.appendChild(p);
    }
  }

  function tick(id, value) {
    const el = document.getElementById(id);
    if (el.textContent !== String(value)) {
      el.textContent = value;
      el.classList.remove("tick");
      void el.offsetWidth;                    // relance l'animation
      el.classList.add("tick");
    }
  }

  function render(st) {
    document.getElementById("bug").style.display = "flex";
    document.getElementById("empty").style.display = "none";
    tick("p1", st.score_me);
    tick("p2", st.score_opp);
    const stw = (st.config && st.config.setsToWin) || 2;
    pips(document.getElementById("d1"), st.sets_me, stw);
    pips(document.getElementById("d2"), st.sets_opp, stw);
    document.getElementById("setlab").textContent = "SET " + st.current_set;
  }

  async function pick() {
    // Actif le plus récent, sinon le plus récent tout statut (le final reste
    // affiché). Requête parent `matches` : l'ORDER BY porte sur matches.
    for (const active of [true, false]) {
      let url = REST + "/matches?select=started_at,match_state!inner(status,current_set,score_me,score_opp,sets_me,sets_opp,config)"
        + "&channel=eq." + encodeURIComponent(CHANNEL)
        + "&order=started_at.desc.nullslast&limit=1";
      if (active) url += "&match_state.status=eq.active";
      const res = await fetch(url, { headers: HEADERS });
      if (res.ok) {
        const data = await res.json();
        if (data.length) { render(data[0].match_state); return; }
      }
    }
    document.getElementById("bug").style.display = "none";
    document.getElementById("empty").style.display = "block";
  }

  pick();
  setInterval(pick, 2000);
});
