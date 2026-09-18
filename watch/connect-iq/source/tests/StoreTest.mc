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
function test_store_prefs(logger as Logger) as Boolean {
    MatchStore.savePresetIndex(1);
    Test.assertEqualMessage(1, MatchStore.loadPresetIndex(), "prefs : format 15 pts memorise");
    MatchStore.savePresetIndex(2);         // hygiene : valeur par defaut
    return true;
}
