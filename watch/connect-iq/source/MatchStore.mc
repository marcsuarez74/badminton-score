import Toybox.Application.Storage;
import Toybox.Lang;

// Persistance du match (spec §7.2, Phase 3). Application.Storage : 8 Ko/valeur,
// 128 Ko au total — découpage en meta + lots plats de 30 events (6 Numbers par
// event, jamais d'imbrication). Écriture à chaque mutation (setValue synchrone).
module MatchStore {
    const META_KEY = "badminton_meta_v1";
    const EVT_PREFIX = "badminton_events_v1.";
    const PREFS_KEY = "badminton_prefs_v1";
    const CHUNK = 30;         // events par lot (~1,5 Ko < 8 Ko)
    const KEEP = 175;         // events conservés après purge (§7.2 : borné 200, purge par lots)

    // ---- préférence format (§5 : mémorisé pour les matchs suivants) ----

    function savePresetIndex(i as Number) as Void {
        Storage.setValue(PREFS_KEY, i);
    }

    function loadPresetIndex() as Number {
        var v = Storage.getValue(PREFS_KEY);
        return (v == null) ? 2 : v;        // défaut : 21 POINTS
    }

    // ---- match ----

    // Sauvegarde synchrone : purge éventuelle, lots d'events, meta.
    function saveMatch(engine as ScoreEngine, presetIndex as Number) as Void {
        engine.trimEvents(KEEP);           // no-op si journal ≤ KEEP (§7.2)
        var events = engine.getEvents();
        var chunk = 0;
        var i = 0;
        while (i < events.size()) {
            var flat = [];
            var stop = i + CHUNK;
            if (stop > events.size()) { stop = events.size(); }
            for (var j = i; j < stop; j += 1) {
                var ev = events[j];
                for (var k = 0; k < 6; k += 1) {
                    flat.add(ev[k]);
                }
            }
            Storage.setValue(EVT_PREFIX + chunk, flat);
            chunk += 1;
            i = stop;
        }
        // supprime les lots orphelins (journal rétréci / nouveau match)
        while (Storage.getValue(EVT_PREFIX + chunk) != null) {
            Storage.deleteValue(EVT_PREFIX + chunk);
            chunk += 1;
        }
        var meta = {
            "v" => 1,
            "mid" => engine.getMatchId(),
            "pi" => presetIndex,
            "pf" => 1,                     // pendingFrom : rien d'acquitté en Phase 3 (§7.2)
            "ls" => engine.getLastSequence(),
            "base" => engine.getBaseState()
        };
        Storage.setValue(META_KEY, meta);
    }

    // Retourne null si aucun match persisté, sinon
    // { "mid", "pi", "ls", "base", "events" } — events = Array de 6-slots.
    function loadMatch() as Dictionary or Null {
        var meta = Storage.getValue(META_KEY) as Dictionary;
        if (meta == null) { return null; }
        var events = [];
        var chunk = 0;
        while (true) {
            var flat = Storage.getValue(EVT_PREFIX + chunk);
            if (flat == null) { break; }
            for (var i = 0; i + 5 < flat.size(); i += 6) {
                events.add([flat[i], flat[i + 1], flat[i + 2], flat[i + 3], flat[i + 4], flat[i + 5]]);
            }
            chunk += 1;
        }
        return {
            "mid" => meta["mid"],
            "pi" => meta["pi"],
            "ls" => meta["ls"],
            "base" => meta["base"],
            "events" => events
        };
    }

    function clearMatch() as Void {
        Storage.deleteValue(META_KEY);
        var chunk = 0;
        while (Storage.getValue(EVT_PREFIX + chunk) != null) {
            Storage.deleteValue(EVT_PREFIX + chunk);
            chunk += 1;
        }
    }
}
