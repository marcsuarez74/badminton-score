import Toybox.Lang;
import Toybox.Test;

// ---- MatchStore : persistance §7.2 (Phase 3) ----

(:test)
function test_store_roundtrip(logger as Logger) as Boolean {
    MatchStore.clearMatch();               // état propre avant test
    var e = new ScoreEngine(MatchPresets.get(2), "mP");
    enginePoints(e, 21, 19);
    e.changeSet();                         // 42 events, set 2, 0-0, sets 1-0
    MatchStore.saveMatch(e, 2);
    var loaded = MatchStore.loadMatch();
    Test.assertEqualMessage(loaded != null, true, "meta presente apres save");
    Test.assertEqualMessage("mP", loaded["mid"], "matchId restaure");
    Test.assertEqualMessage(2, loaded["pi"], "preset index restaure");
    Test.assertEqualMessage(42, loaded["ls"], "lastSequence restaure");
    Test.assertEqualMessage(42, loaded["events"].size(), "42 events restaures");
    var e2 = new ScoreEngine(MatchPresets.get(2), loaded["mid"]);
    e2.restore(loaded["base"], loaded["events"]);
    Test.assertEqualMessage(0, e2.getPhase(), "restore : PLAYING (set 2)");
    Test.assertEqualMessage(2, e2.getSetNumber(), "restore : set 2");
    Test.assertEqualMessage(1, e2.getSetsMe(), "restore : sets 1-0");
    MatchStore.clearMatch();
    Test.assertEqualMessage(MatchStore.loadMatch() == null, true, "clear : plus de meta");
    return true;
}

(:test)
function test_store_chunks_41_events(logger as Logger) as Boolean {
    MatchStore.clearMatch();
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);               // 41 events (40 POINT + SET_FINISHED)
    MatchStore.saveMatch(e, 2);            // 41 > 30 : au moins 2 lots
    var loaded = MatchStore.loadMatch();
    Test.assertEqualMessage(41, loaded["events"].size(), "41 events via plusieurs lots");
    Test.assertEqualMessage(41, loaded["events"][40][2], "dernier event : seq 41");
    Test.assertEqualMessage(ScoreEvent.TYPE_SET_FINISHED, loaded["events"][40][0], "dernier = SET_FINISHED");
    MatchStore.clearMatch();
    return true;
}

(:test)
function test_store_orphan_chunks(logger as Logger) as Boolean {
    MatchStore.clearMatch();
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);               // 41 events → 2 lots (30 + 11)
    MatchStore.saveMatch(e, 2);
    var e2 = new ScoreEngine(MatchPresets.get(0), "m2");   // nouveau match plus court, MÊME storage
    enginePoints(e2, 5, 3);                // 8 events → 1 lot seulement
    MatchStore.saveMatch(e2, 0);           // le lot 1 (11 events du match 1) doit être purgé
    var loaded = MatchStore.loadMatch();
    Test.assertEqualMessage("m2", loaded["mid"], "meta du match 2");
    Test.assertEqualMessage(8, loaded["events"].size(), "8 events — pas d'orphelin relu");
    Test.assertEqualMessage(8, loaded["events"][7][2], "dernier event : seq 8");
    MatchStore.clearMatch();
    return true;
}

(:test)
function test_store_prefs(logger as Logger) as Boolean {
    MatchStore.savePresetIndex(1);
    Test.assertEqualMessage(1, MatchStore.loadPresetIndex(), "prefs : format 15 pts memorise");
    MatchStore.savePresetIndex(2);         // hygiene : valeur par defaut
    return true;
}

// ---- sync (Phase 4a) : pointeur d'acquittement pf ----

(:test)
function test_store_pf_default_et_ack(logger as Logger) as Boolean {
    MatchStore.clearMatch();               // état propre avant test
    var engine = new ScoreEngine(MatchPresets.get(2), "PFX");
    engine.pointMe();
    MatchStore.saveMatch(engine, 2);
    Test.assertEqualMessage(1, MatchStore.getPendingFrom(), "pf défaut = 1");
    MatchStore.ackUntil(1);
    Test.assertEqualMessage(2, MatchStore.getPendingFrom(), "pf=2 après ack");
    MatchStore.ackUntil(1);                // un ack plus ancien ne recule pas pf
    Test.assertEqualMessage(2, MatchStore.getPendingFrom(), "pf ne recule pas");
    MatchStore.clearMatch();
    return true;
}

(:test)
function test_store_pf_preserve_apres_save(logger as Logger) as Boolean {
    MatchStore.clearMatch();
    var engine = new ScoreEngine(MatchPresets.get(2), "PFX");
    engine.pointMe();
    MatchStore.saveMatch(engine, 2);
    MatchStore.ackUntil(3);                // ack hypothétique au-delà du journal → pf=4
    engine.pointMe();
    MatchStore.saveMatch(engine, 2);       // re-save du MÊME match
    Test.assertEqualMessage(4, MatchStore.getPendingFrom(), "pf doit être préservé");
    MatchStore.clearMatch();
    return true;
}

(:test)
function test_store_pf_reset_nouveau_match(logger as Logger) as Boolean {
    MatchStore.clearMatch();
    var engine = new ScoreEngine(MatchPresets.get(2), "PFX");
    engine.pointMe();
    MatchStore.saveMatch(engine, 2);
    MatchStore.ackUntil(1);
    var other = new ScoreEngine(MatchPresets.get(2), "PF2");
    other.pointMe();
    MatchStore.saveMatch(other, 2);        // matchId différent → pf repart à 1
    Test.assertEqualMessage(1, MatchStore.getPendingFrom(), "pf reset nouveau match");
    MatchStore.clearMatch();
    return true;
}
