"""Tests du pick() du renderer VPS — même logique que l'overlay (phase 5).

pick() interroge PostgREST (matches parent + match_state!inner) :
  1er passage : actif le plus récent
  2e passage (fallback) : le plus récent tout statut
Contrat : retourne un dict normalisé ou None (canal inconnu, erreur réseau).
"""

import json
import urllib.error

import pytest

from renderer import pick, make_url, KEEP


ANON = "anon-key-test"

MATCH_STATE_ACTIVE = {
    "status": "active",
    "current_set": 1,
    "score_me": 5,
    "score_opp": 3,
    "sets_me": 1,
    "sets_opp": 0,
    "config": {"setsToWin": 2},
}

ROW_ACTIVE = {"started_at": "2026-09-23T10:00:00Z", "match_state": MATCH_STATE_ACTIVE}
ROW_FINISHED = {
    "started_at": "2026-09-23T09:00:00Z",
    "match_state": {**MATCH_STATE_ACTIVE, "status": "finished"},
}


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
    url = make_url("https://sb.example.co", ANON, "marc", active=True)
    assert "select=started_at," in url
    assert "match_state!inner(status" in url
    assert "channel=eq.marc" in url
    assert "match_state.status=eq.active" in url
    assert "order=started_at.desc.nullslast" in url
    assert "limit=1" in url


def test_url_fallback_sans_filtre_actif():
    url = make_url("https://sb.example.co", ANON, "marc", active=False)
    assert "match_state.status=eq.active" not in url


def test_actif_plus_recent_gagne():
    fetch = FakeFetch([[ROW_ACTIVE]])
    state = pick("marc", "https://sb.example.co", ANON, fetch=fetch)
    assert state["score_me"] == 5
    assert state["score_opp"] == 3
    assert state["sets_me"] == 1
    assert state["sets_opp"] == 0
    assert state["current_set"] == 1
    assert state["sets_to_win"] == 2
    assert len(fetch.calls) == 1  # pas de fallback nécessaire


def test_fallback_dernier_fini_si_pas_dactif():
    # 1er passage (actif) : vide ; 2e (tout statut) : le dernier fini
    fetch = FakeFetch([[], [ROW_FINISHED]])
    state = pick("marc", "https://sb.example.co", ANON, fetch=fetch)
    assert state["score_me"] == 5
    assert len(fetch.calls) == 2


def test_canal_inconnu_retourne_none():
    fetch = FakeFetch([[], []])
    assert pick("inconnu", "https://sb.example.co", ANON, fetch=fetch) is None


def test_erreur_reseau_retourne_none_pas_dexception():
    fetch = FakeFetch([urllib.error.URLError("boom"), urllib.error.URLError("boom")])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_erreur_reseau_mode_keep_renvoie_sentinelle():
    # Le main utilise on_error=KEEP pour distinguer « aucun match »
    # (→ frame transparente) de « Supabase injoignable » (→ dernière frame).
    fetch = FakeFetch([urllib.error.URLError("boom")])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch, on_error=KEEP) is KEEP


def test_mauvais_json_retourne_none():
    fetch = FakeFetch([json.JSONDecodeError("bad", "doc", 0), json.JSONDecodeError("bad", "doc", 0)])
    assert pick("marc", "https://sb.example.co", ANON, fetch=fetch) is None


def test_sets_to_win_par_defaut_2_si_config_absent():
    fetch = FakeFetch([[{**ROW_ACTIVE, "match_state": {**MATCH_STATE_ACTIVE, "config": None}}]])
    state = pick("marc", "https://sb.example.co", ANON, fetch=fetch)
    assert state["sets_to_win"] == 2
