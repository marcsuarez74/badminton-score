import Toybox.Lang;
import Toybox.Test;

// ---- MatchConfig / presets ----

(:test)
function test_presets_values(logger as Logger) as Boolean {
    var c11 = MatchPresets.get(0);
    Test.assertEqualMessage(11, c11.mTargetScore, "11 pts target");
    Test.assertEqualMessage(0, c11.mCap, "11 pts sans plafond");
    var c15 = MatchPresets.get(1);
    Test.assertEqualMessage(15, c15.mTargetScore, "15 pts target");
    Test.assertEqualMessage(21, c15.mCap, "15 pts cap 21");
    var c21 = MatchPresets.get(2);
    Test.assertEqualMessage(21, c21.mTargetScore, "21 pts target");
    Test.assertEqualMessage(30, c21.mCap, "21 pts cap 30");
    Test.assertEqualMessage(3, MatchPresets.count(), "3 presets");
    Test.assertEqualMessage(2, c21.mWinBy, "winBy 2");
    Test.assertEqualMessage(2, c21.mSetsToWin, "setsToWin 2");
    return true;
}

// ---- Rules.isSetOver (spec §4.2) ----

(:test)
function test_rules_21_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(2);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 19), "20-19 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 21, 20), "21-20 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 19), "21-19 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 29, 29), "29-29 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 30, 29), "30-29 fini (cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 19, 21), "19-21 fini (adversaire)");
    return true;
}

(:test)
function test_rules_15_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(1);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 14, 14), "14-14 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 15, 13), "15-13 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 20), "21-20 fini (cap 21)");
    return true;
}

(:test)
function test_rules_11_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(0);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 10, 10), "10-10 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 11, 10), "11-10 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 11, 9), "11-9 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (sans cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 16, 14), "16-14 fini (sans cap, ecart 2)");
    return true;
}

// ---- ScoreEngine : points + replay + fin de set auto (spec §4.2/§4.3, §15.1) ----

// Compte n points par côté en alternant (helper de test — l'alternance évite
// de déclencher SET_FINISHED prématurément, ex. 11-0 sur le preset 21).
// NB : paramètre `nMe` car `me` est un mot réservé Monkey C.
function enginePoints(e as ScoreEngine, nMe as Number, opp as Number) as Void {
    var i = 0;
    var j = 0;
    while (i < nMe || j < opp) {
        if (i < nMe) { e.pointMe(); i += 1; }
        if (j < opp) { e.pointOpponent(); j += 1; }
    }
}

(:test)
function test_engine_initial_state(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    Test.assertEqualMessage(0, e.getScoreMe(), "score me 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "score opp 0-0");
    Test.assertEqualMessage(1, e.getSetNumber(), "set 1");
    Test.assertEqualMessage(0, e.getSetsMe(), "sets me 0");
    Test.assertEqualMessage(0, e.getSetsOpp(), "sets opp 0");
    Test.assertEqualMessage(0, e.getPhase(), "phase PLAYING");
    return true;
}

(:test)
function test_engine_points_and_replay(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    Test.assertEqualMessage(1, e.getScoreMe(), "1-0 apres POINT_ME");
    e.pointOpponent();
    e.pointOpponent();
    Test.assertEqualMessage(1, e.getScoreMe(), "score me 1");
    Test.assertEqualMessage(2, e.getScoreOpp(), "1-2 apres 2 POINT_OPPONENT");
    Test.assertEqualMessage(3, e.getEvents().size(), "journal = 3 events (1 POINT_ME + 2 POINT_OPPONENT)");
    Test.assertEqualMessage(0, e.getPhase(), "toujours PLAYING");
    return true;
}

(:test)
function test_engine_deuce_21(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 20, 20);
    Test.assertEqualMessage(0, e.getPhase(), "20-20 pas fini");
    e.pointMe();
    Test.assertEqualMessage(21, e.getScoreMe(), "21-20");
    Test.assertEqualMessage(0, e.getPhase(), "21-20 : set NON fini (deuce)");
    return true;
}

(:test)
function test_engine_cap_21(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 29, 29);
    e.pointMe();
    Test.assertEqualMessage(30, e.getScoreMe(), "30-29");
    Test.assertEqualMessage(1, e.getPhase(), "cap atteint -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    return true;
}

(:test)
function test_engine_set_finished_normal(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);
    Test.assertEqualMessage(1, e.getPhase(), "21-19 -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    Test.assertEqualMessage(21, e.getLastSetScoreMe(), "dernier set 21");
    Test.assertEqualMessage(19, e.getLastSetScoreOpp(), "dernier set 19");
    Test.assertEqualMessage(1, e.getSetNumber(), "setNumber toujours 1 tant que pas de transition");
    return true;
}

(:test)
function test_engine_set_finished_opponent(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 19, 21);
    Test.assertEqualMessage(1, e.getPhase(), "19-21 -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsOpp(), "sets 0-1");
    return true;
}

(:test)
function test_engine_deuce_15(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(1), "m1");
    enginePoints(e, 14, 14);
    e.pointMe();
    Test.assertEqualMessage(15, e.getScoreMe(), "15-14");
    Test.assertEqualMessage(0, e.getPhase(), "15-14 : set NON fini");
    return true;
}

(:test)
function test_engine_cap_15(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(1), "m1");
    enginePoints(e, 20, 20);
    e.pointMe();
    Test.assertEqualMessage(21, e.getScoreMe(), "21-20");
    Test.assertEqualMessage(1, e.getPhase(), "cap 21 -> SET_RESULT");
    return true;
}

(:test)
function test_engine_deuce_11(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(0), "m1");
    enginePoints(e, 10, 10);
    e.pointMe();
    Test.assertEqualMessage(11, e.getScoreMe(), "11-10");
    Test.assertEqualMessage(0, e.getPhase(), "11-10 : set NON fini");
    return true;
}

(:test)
function test_engine_no_cap_11(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(0), "m1");
    enginePoints(e, 15, 14);
    Test.assertEqualMessage(0, e.getPhase(), "15-14 non fini (sans plafond)");
    e.pointMe();
    Test.assertEqualMessage(16, e.getScoreMe(), "16-14");
    Test.assertEqualMessage(1, e.getPhase(), "16-14 fini (ecart 2, sans plafond)");
    return true;
}

(:test)
function test_engine_match_finished_2_sets(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getSetsMe(), "sets 2-0");
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    Test.assertEqualMessage(46, e.getEvents().size(),
        "journal: 42 points + 2 SET_FINISHED + 1 SET_CHANGED + 1 MATCH_FINISHED");
    e.pointMe();   // sans effet : match verrouillé (§4.5)
    Test.assertEqualMessage(46, e.getEvents().size(), "point ignore apres MATCH_FINISHED");
    Test.assertEqualMessage(21, e.getScoreMe(), "scores du dernier set figes 21-0");
    return true;
}

(:test)
function test_engine_manual_set_change_finishes_match(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);
    e.changeSet();                    // set 2
    enginePoints(e, 15, 2);
    e.changeSet();                    // changement manuel : leader crédité -> 2-0
    Test.assertEqualMessage(2, e.getSetsMe(), "sets 2-0 via SET_CHANGED manuel");
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED (spec §4.3)");
    Test.assertEqualMessage(42, e.getEvents().size(),
        "journal: 38 points + 1 SET_FINISHED + 2 SET_CHANGED + 1 MATCH_FINISHED");
    e.changeSet();
    Test.assertEqualMessage(42, e.getEvents().size(), "verrou : plus de mutation");
    return true;
}

// ---- ScoreEngine : transitions de set (spec §4.4, §15.1) ----

(:test)
function test_engine_set_result_transition(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);
    Test.assertEqualMessage(1, e.getPhase(), "SET_RESULT apres 21-19");
    e.changeSet();
    Test.assertEqualMessage(0, e.getPhase(), "PLAYING apres set suivant");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    Test.assertEqualMessage(0, e.getScoreMe(), "set 2 : 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "set 2 : 0-0");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0 conserves");
    return true;
}

(:test)
function test_engine_manual_set_change_leader_credited(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 5, 3);
    e.changeSet();   // changement manuel assumé : leader strict crédité
    Test.assertEqualMessage(0, e.getPhase(), "PLAYING apres changement manuel");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    Test.assertEqualMessage(1, e.getSetsMe(), "leader (5-3) credite : sets 1-0");
    return true;
}

(:test)
function test_engine_manual_set_change_tie_not_credited(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 3, 3);
    e.changeSet();   // égalité : personne n'est crédité
    Test.assertEqualMessage(0, e.getSetsMe(), "egalite : sets me 0");
    Test.assertEqualMessage(0, e.getSetsOpp(), "egalite : sets opp 0");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2 quand meme");
    return true;
}

// ---- ScoreEngine : UNDO (spec §4.5/D7, §15.1) ----

(:test)
function test_engine_undo_simple(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    e.undo();
    Test.assertEqualMessage(0, e.getScoreMe(), "undo simple : retour 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "undo simple : retour 0-0");
    Test.assertEqualMessage(0, e.getPhase(), "undo simple : PLAYING");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide apres undo");
    return true;
}

(:test)
function test_engine_undo_multi(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 2, 1);
    Test.assertEqualMessage(2, e.getScoreMe(), "2-1 avant undo");
    e.undo();
    e.undo();
    e.undo();
    Test.assertEqualMessage(0, e.getScoreMe(), "undo x3 : 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "undo x3 : pas de negatif");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide");
    return true;
}

(:test)
function test_engine_undo_empty(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.undo();   // journal vide : sans effet
    Test.assertEqualMessage(0, e.getScoreMe(), "undo vide : 0-0");
    Test.assertEqualMessage(0, e.getEvents().size(), "undo vide : journal intact");
    Test.assertEqualMessage(1, e.getSetNumber(), "undo vide : set 1");
    return true;
}

(:test)
function test_engine_undo_match_finished_refused(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    var count = e.getEvents().size();
    e.undo();   // D7 : MATCH_FINISHED ne s'annule jamais
    Test.assertEqualMessage(count, e.getEvents().size(), "undo refuse sur match fini");
    Test.assertEqualMessage(2, e.getPhase(), "toujours MATCH_FINISHED");
    return true;
}

(:test)
function test_engine_undo_set_finished(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);          // SET_FINISHED auto (§4.2)
    Test.assertEqualMessage(1, e.getPhase(), "SET_RESULT apres 21-19");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    e.undo();                          // reprendre le set terminé
    Test.assertEqualMessage(0, e.getPhase(), "set repris : PLAYING");
    Test.assertEqualMessage(21, e.getScoreMe(), "score du set restaure : 21");
    Test.assertEqualMessage(19, e.getScoreOpp(), "score du set restaure : 19");
    Test.assertEqualMessage(0, e.getSetsMe(), "sets recalcules : 0-0");
    Test.assertEqualMessage(40, e.getEvents().size(), "journal : 41 - 1");
    return true;
}

(:test)
function test_engine_undo_set_changed(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);
    e.changeSet();                     // SET_CHANGED apres SET_FINISHED
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    e.undo();                          // retour au set précédent
    Test.assertEqualMessage(1, e.getPhase(), "retour : SET_RESULT (fin du set 1 toujours enregistrée)");
    Test.assertEqualMessage(1, e.getSetNumber(), "retour au set 1");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    Test.assertEqualMessage(21, e.getLastSetScoreMe(), "score du set 1 restaure");
    Test.assertEqualMessage(19, e.getLastSetScoreOpp(), "19");
    return true;
}

// ---- ScoreEngine : protocole d'événements (spec §7.1/§8.2, décision D-2) ----

(:test)
function test_engine_events_protocol(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    e.pointOpponent();
    e.pointMe();
    Test.assertEqualMessage(3, e.getEvents().size(), "3 events");
    // id = matchId:sequence, unique (§8.2)
    Test.assertEqualMessage("m1:1", e.getEventId(0), "id 1 = m1:1");
    Test.assertEqualMessage("m1:2", e.getEventId(1), "id 2 = m1:2");
    Test.assertEqualMessage("m1:3", e.getEventId(2), "id 3 = m1:3");
    // sequence sans trou depuis 1 (§8.2)
    Test.assertEqualMessage(1, e.getEvent(0)[2], "seq 1");
    Test.assertEqualMessage(2, e.getEvent(1)[2], "seq 2");
    Test.assertEqualMessage(3, e.getEvent(2)[2], "seq 3");
    // timestamp present (System.getTimer() > 0 en simu)
    Test.assertEqualMessage(true, e.getEvent(0)[3] > 0, "ts > 0");
    // previousScore cohérent : état dérivé avant chaque mutation
    Test.assertEqualMessage(0, e.getEvent(0)[4], "e1 prev me 0");
    Test.assertEqualMessage(0, e.getEvent(0)[5], "e1 prev opp 0");
    Test.assertEqualMessage(1, e.getEvent(1)[4], "e2 prev me 1");
    Test.assertEqualMessage(0, e.getEvent(1)[5], "e2 prev opp 0");
    Test.assertEqualMessage(1, e.getEvent(2)[4], "e3 prev me 1");
    Test.assertEqualMessage(1, e.getEvent(2)[5], "e3 prev opp 1");
    // newScore du dernier event = état courant (2-1)
    Test.assertEqualMessage(2, e.getScoreMe(), "new dernier event : me 2");
    Test.assertEqualMessage(1, e.getScoreOpp(), "new dernier event : opp 1");
    return true;
}

(:test)
function test_engine_events_set_finished_metadata(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);
    var n = e.getEvents().size();      // 40 points + SET_FINISHED
    Test.assertEqualMessage(41, n, "41 events");
    var fin = e.getEvent(n - 1);
    Test.assertEqualMessage(ScoreEvent.TYPE_SET_FINISHED, fin[0], "dernier = SET_FINISHED");
    Test.assertEqualMessage(41, fin[2], "seq 41 (les points comptent aussi, §8.2)");
    Test.assertEqualMessage(21, fin[4], "prev me 21");
    Test.assertEqualMessage(19, fin[5], "prev opp 19");
    return true;
}

(:test)
function test_engine_undo_sequence_monotonic(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    e.undo();
    e.pointMe();
    Test.assertEqualMessage(1, e.getEvents().size(), "1 event apres undo+nouveau");
    Test.assertEqualMessage(2, e.getEvent(0)[2], "sequence jamais reutilisee : 2, pas 1 (D-2)");
    Test.assertEqualMessage("m1:2", e.getEventId(0), "id m1:2");
    return true;
}

(:test)
function test_engine_match_locked(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    var count = e.getEvents().size();
    e.changeSet();   // sans effet sur un match fini
    Test.assertEqualMessage(count, e.getEvents().size(), "changeSet ignore apres MATCH_FINISHED");
    e.pointMe();     // sans effet non plus
    Test.assertEqualMessage(count, e.getEvents().size(), "point ignore apres MATCH_FINISHED");
    return true;
}

(:test)
function test_engine_new_match_reset(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);
    e.changeSet();
    e.newMatch(MatchPresets.get(0), "m2");   // nouveau match en 11 pts, nouvel id
    Test.assertEqualMessage(0, e.getScoreMe(), "reset 0-0");
    Test.assertEqualMessage(1, e.getSetNumber(), "reset set 1");
    Test.assertEqualMessage(0, e.getPhase(), "reset PLAYING");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide");
    Test.assertEqualMessage(11, e.getConfig().mTargetScore, "nouvelle config 11 pts");
    return true;
}
