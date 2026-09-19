import Toybox.Lang;
import Toybox.Test;

// Tests des modules de sync (Phase 4a). Exécutés via Run No Evil (monkeyc -t).
module SyncTests {

    // ---- MatchIds ----

    (:test)
    function test_matchid_format(logger as Logger) as Boolean {
        var id = MatchIds.generate();
        if (!MatchIds.isValid(id)) { logger.debug("format invalide: " + id); return false; }
        return true;
    }

    (:test)
    function test_matchid_deux_generations_differentes(logger as Logger) as Boolean {
        var a = MatchIds.generate();
        var b = MatchIds.generate();
        if (a.equals(b)) { logger.debug("collision improbable: " + a); return false; }
        return true;
    }

    (:test)
    function test_matchid_isvalide_rejete(logger as Logger) as Boolean {
        if (MatchIds.isValid("IILOOOXY")) { return false; }   // I/L/O interdits (Crockford)
        if (MatchIds.isValid("ABC")) { return false; }         // longueur ≠ 8
        if (MatchIds.isValid(null)) { return false; }
        return true;
    }

    // ---- DeviceId ----

    (:test)
    function test_deviceid_stable(logger as Logger) as Boolean {
        var a = DeviceId.getOrCreate();
        var b = DeviceId.getOrCreate();
        if (!a.equals(b)) { logger.debug("deviceId instable"); return false; }
        return true;
    }

    (:test)
    function test_deviceid_format(logger as Logger) as Boolean {
        var id = DeviceId.getOrCreate();
        if (id.length() != 16) { logger.debug("longueur != 16"); return false; }
        var hex = "0123456789abcdef";
        for (var i = 0; i < 16; i += 1) {
            var c = id.substring(i, i + 1);
            var found = false;
            for (var j = 0; j < 16; j += 1) {
                if (hex.substring(j, j + 1).equals(c)) { found = true; break; }
            }
            if (!found) { logger.debug("caractère non hex: " + c); return false; }
        }
        return true;
    }

    // ---- SyncCore ----

    // Fixture : engine 21 pts avec n points MOI.
    function _enginePoints(n as Number) as ScoreEngine {
        var e = new ScoreEngine(MatchPresets.get(2), "T1");
        for (var i = 0; i < n; i += 1) { e.pointMe(); }
        return e;
    }

    (:test)
    function test_core_batchslice_premier_batch(logger as Logger) as Boolean {
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(8).getEvents(), 1, 5);
        if (batch.size() != 5) { logger.debug("attendu 5"); return false; }
        if (batch[0][2] != 1 || batch[4][2] != 5) { logger.debug("seqs 1..5 attendues"); return false; }
        return true;
    }

    (:test)
    function test_core_batchslice_deuxieme_batch(logger as Logger) as Boolean {
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(8).getEvents(), 6, 5);
        if (batch.size() != 3) { logger.debug("attendu 3"); return false; }
        if (batch[0][2] != 6 || batch[2][2] != 8) { logger.debug("seqs 6..8 attendues"); return false; }
        return true;
    }

    (:test)
    function test_core_batchslice_pf_deja_purge(logger as Logger) as Boolean {
        // pf pointe au-delà du journal (events acquittés purgés/undo) → vide.
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(4).getEvents(), 50, 5);
        if (batch.size() != 0) { logger.debug("attendu vide"); return false; }
        return true;
    }

    (:test)
    function test_core_serialize_event(logger as Logger) as Boolean {
        var core = new SyncCore();
        var e = core.serializeEvent([0, 0, 7, 123l, 2, 1]);
        if (e["type"] != 0 || e["arg"] != 0 || e["sequence"] != 7) { return false; }
        if (e["ts"] != 123l || e["prevMe"] != 2 || e["prevOpp"] != 1) { return false; }
        return true;
    }

    (:test)
    function test_core_buildbody(logger as Logger) as Boolean {
        var core = new SyncCore();
        var engine = _enginePoints(3);
        var body = core.buildBody(engine, "dev123", core.batchSlice(engine.getEvents(), 1, 5));
        var snap = body["snapshot"];
        if (!body["deviceId"].equals("dev123")) { return false; }
        if (!snap["status"].equals("active") || snap["scoreMe"] != 3 || snap["scoreOpp"] != 0) { return false; }
        if (snap["currentSet"] != 1 || snap["setsMe"] != 0 || snap["setsOpp"] != 0) { return false; }
        if (snap["lastSequence"] != 3) { return false; }
        if (body["config"]["targetScore"] != 21) { return false; }
        if (body["events"].size() != 3) { return false; }
        return true;
    }

    (:test)
    function test_core_snapshot_match_finished(logger as Logger) as Boolean {
        var core = new SyncCore();
        var e = new ScoreEngine(MatchPresets.get(2), "T1");
        for (var i = 0; i < 21; i += 1) { e.pointMe(); }    // set 1 fini → SET_RESULT
        e.changeSet();                                      // « set suivant » (pointMe no-op hors PLAYING)
        for (var i = 0; i < 21; i += 1) { e.pointMe(); }    // set 2 fini → MATCH_FINISHED
        if (!core.statusString(e.getPhase()).equals("match_finished")) { logger.debug("match_finished attendu"); return false; }
        return true;
    }

    (:test)
    function test_core_backoff_sequence(logger as Logger) as Boolean {
        var core = new SyncCore();
        if (core.nextBackoffMs(0) != 10000l) { return false; }
        if (core.nextBackoffMs(1) != 20000l) { return false; }
        if (core.nextBackoffMs(2) != 40000l) { return false; }
        if (core.nextBackoffMs(3) != 80000l) { return false; }
        if (core.nextBackoffMs(4) != 120000l) { return false; }
        if (core.nextBackoffMs(9) != 120000l) { return false; }   // cap 2 min
        return true;
    }

    (:test)
    function test_core_shouldsend(logger as Logger) as Boolean {
        var core = new SyncCore();
        if (core.shouldSend(10000l, 0l, false, 0l) != true) { return false; }        // 1er envoi
        if (core.shouldSend(10000l, 8000l, false, 0l) != false) { return false; }    // < 5 s
        if (core.shouldSend(10000l, 5000l, true, 0l) != false) { return false; }     // en vol
        if (core.shouldSend(10000l, 0l, false, 20000l) != false) { return false; }   // backoff
        if (core.shouldSend(30000l, 0l, false, 20000l) != true) { return false; }    // backoff écoulé
        return true;
    }
}
