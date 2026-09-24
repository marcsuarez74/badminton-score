"""Tests du pick() du renderer VPS — même logique que l'overlay (phase 5).

pick() interroge PostgREST (matches parent + match_state!inner) :
  un seul passage : le match ACTIF le plus récent, mais seulement s'il est
  FRAIS (sync récent ≤ stale_s). Un match actif laissé sans sync (quitté,
  montre hors ligne) devient « fantôme » et doit disparaître de l'overlay.
Contrat : retourne un dict normalisé, ou None (aucun match frais, canal
inconnu, erreur réseau).
"""

import json
import urllib.error
from datetime import datetime, timedelta, timezone

import pytest

from renderer import pick, make_url, KEEP


ANON = "anon-key-test"


def iso_ago(seconds):
    """Horodatage ISO UTC datant de `seconds` — comme Supabase (timestamptz)."""
    ts = datetime.now(timezone.utc) - timedelta(seconds=seconds)
    return ts.strftime("%Y-%m-%dT%H:%M:%S+00:00")


def state_row(seconds_ago=5, status="active"):
    return {
        "started_at": "2026-09-23T10:00:00Z",
        "match_state": {
            "status": status,
            "updated_at": iso_ago(seconds_ago),
            "current_set": 1,
            "score_me": 5,
            "score_opp": 3,
            "sets_me": 1,
            "sets_opp": 0,
            "config": {"setsToWin": 2},
        },
    }


ROW_ACTIVE = state_row(5)                     # actif, sync il y a 5 s
ROW_FINISHED = state_row(5, status="finished")


class FakeFetch:
    """Fetch injectable : séquence de réponses ou d'exceptions."""

    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, url):
        self.calls.append(url)
        r = self.responses.pop(0)
        if isinstance(r, Exception):
            raise r
        return r


def test_url_contient_select_parent_et_inner():
    url = make_url("https://sb.example.co", ANON, "marc")
    assert "select=started_at," in url
    assert "match_state!inner(status" in url
    assert "updated_at" in url
    assert "channel=eq.marc" in url
    assert "match_state.status=eq.active" in url
    assert "order=started_at.desc.nullslast" in url
    assert "limit=1" in url


def test_actif_frais_gagne():
    fetch = FakeFetch([[ROW_ACTIVE]])
    state = pick("marc", "https://sb.example.co", ANON, fetch=fetch)
    assert state["score_me"] == 5
    assert state["score_opp"] == 3
    assert state["sets_me"] == 1
    assert state["sets_opp"] == 0
    assert state["current_set"] == 1
    assert state["sets_to_win"] == 2
    assert len(fetch.calls) == 1  # un seul passage, pas de fallback


def test_actif_stale_est_ignore_fantome():
    # Le match quitté reste « active » dans la base mais n'est plus
    # synchronisé : > stale_s → l'overlay doit disparaître (None).
    fetch = FakeFetch([[state_row(1800)]])   # sync il y a 30 min
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_seuil_stale_parametrable():
    fetch = FakeFetch([[state_row(100)]])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch,
                stale_s=60) is None
    fetch = FakeFetch([[state_row(100)]])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch,
                stale_s=300) is not None


def test_match_fini_jamais_affiche():
    # Fin du contrat « le plus récent tout statut » : un match terminé ou
    # quitté n'est plus jamais affiché — l'overlay se réinitialise.
    fetch = FakeFetch([[], [ROW_FINISHED]])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_actif_fraichement_fini_frontiere_stale():
    # La frontière (à ~1 s près, le temps du test s'écoule) : sync récent → frais ;
    # sync plus vieux que stale_s → fantôme.
    fetch = FakeFetch([[state_row(598)]])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch,
                stale_s=600) is not None
    fetch = FakeFetch([[state_row(602)]])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch,
                stale_s=600) is None


def test_canal_inconnu_retourne_none():
    fetch = FakeFetch([[]])
    assert pick("inconnu", "https://sb.example.co", ANON, fetch=fetch) is None


def test_erreur_reseau_retourne_none_pas_dexception():
    fetch = FakeFetch([urllib.error.URLError("boom")])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_erreur_reseau_mode_keep_renvoie_sentinelle():
    # Le main utilise on_error=KEEP pour distinguer « aucun match »
    # (→ frame transparente) de « Supabase injoignable » (→ dernière frame).
    fetch = FakeFetch([urllib.error.URLError("boom")])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch, on_error=KEEP) is KEEP


def test_mauvais_json_retourne_none():
    fetch = FakeFetch([json.JSONDecodeError("bad", "doc", 0)])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_sets_to_win_par_defaut_2_si_config_absent():
    fetch = FakeFetch([[{**ROW_ACTIVE, "match_state": {**MATCH_STATE_ACTIVE_CONFIG_NONE}}]])
    state = pick("marc", "https://sb.example.co", ANON, fetch=fetch)
    assert state["sets_to_win"] == 2


MATCH_STATE_ACTIVE_CONFIG_NONE = {
    **state_row(5)["match_state"],
    "config": None,
}
