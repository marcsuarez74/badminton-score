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
}
