import Toybox.Lang;
import Toybox.Math;

// matchId : 8 caractères Crockford base32 (40 bits) — spec sync §4.2.
// Généré à la startMatch (offline-first, aucun aller-retour) ; unicité
// garantie en pratique + contrainte PK backend en filet (409 → régénération).
module MatchIds {
    const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";   // sans I/L/O/U

    function generate() as String {
        var id = "";
        for (var i = 0; i < 8; i += 1) {
            var v = Math.rand() & 0x1F;                     // 5 bits par caractère
            id = id + ALPHABET.substring(v, v + 1);
        }
        return id;
    }

    function isValid(id) as Boolean {
        if (id == null || id.length() != 8) { return false; }
        for (var i = 0; i < 8; i += 1) {
            if (!_inAlphabet(id.substring(i, i + 1))) { return false; }
        }
        return true;
    }

    function _inAlphabet(c as String) as Boolean {
        for (var i = 0; i < 32; i += 1) {
            if (ALPHABET.substring(i, i + 1).equals(c)) { return true; }
        }
        return false;
    }
}
