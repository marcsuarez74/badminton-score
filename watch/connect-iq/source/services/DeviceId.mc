import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;

// deviceId : UUID d'installation (64 bits hex) — spec sync §4.2.
// Généré au premier lancement, persisté dans Application.Storage,
// stable par montre/install. 3 montres = 3 deviceIds (même device key).
module DeviceId {
    const KEY = "install_uuid_v1";
    const HEX = "0123456789abcdef";

    function getOrCreate() as String {
        var v = Storage.getValue(KEY);
        if (v != null) { return v as String; }
        var id = "";
        for (var i = 0; i < 16; i += 1) {
            var n = Math.rand() & 0x0F;
            id = id + HEX.substring(n, n + 1);
        }
        Storage.setValue(KEY, id);
        return id;
    }
}
