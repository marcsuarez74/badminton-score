import Toybox.Application.Properties;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Synchronisation montre → backend (Phase 4a, spec sync §7). Jamais bloquant :
// le scoring ne dépend jamais du réseau. Batchs ≤ 5 events + snapshot, une
// seule requête en vol, ≥ 5 s entre débuts (BLE 400-800 o/s), timeout
// applicatif 30 s (le callback makeWebRequest peut ne jamais être appelé,
// §3.8 de la spec sync), backoff 10 s → 2 min.
class SyncService {
    var mCore;
    var mDeviceId;
    var mInFlight = false;
    var mLastAttemptMs = 0l;
    var mBackoffUntilMs = 0l;
    var mErrors = 0;
    var mEngineRef = null;      // dernier engine vu (drain / watchdog)
    var mTimer;                 // watchdog 30 s OU drain — un seul rôle à la fois

    function initialize(deviceId as String) {
        mCore = new SyncCore();
        mDeviceId = deviceId;
        mTimer = new Timer.Timer();
    }

    // Déclencheur : après chaque saveMatch (MatchView.syncScreen / startMatch)
    // et au lancement (flush §9.4). Configuration absente → inactif (graceful).
    function trigger(engine as ScoreEngine or Null) as Void {
        mEngineRef = engine;
        if (engine == null) { return; }
        var url = Properties.getValue("backendUrl");
        var key = Properties.getValue("deviceKey");
        if (url == null || url.equals("") || key == null || key.equals("")) { return; }
        var now = System.getTimer();
        if (!mCore.shouldSend(now, mLastAttemptMs, mInFlight, mBackoffUntilMs)) { return; }
        var batch = mCore.batchSlice(engine.getEvents(), MatchStore.getPendingFrom(), 5);
        if (batch.size() == 0) { return; }
        _send(url, key, engine, batch);
    }

    function _send(url as String, key as String, engine as ScoreEngine, batch as Array) as Void {
        mInFlight = true;
        mLastAttemptMs = System.getTimer();
        var fullUrl = url + "/matches/" + engine.getMatchId() + "/events";
        var body = mCore.buildBody(engine, mDeviceId, batch);
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "X-Device-Key" => key, "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        mTimer.stop();
        mTimer.start(method(:_onTimeout), 30000, false);
        Communications.makeWebRequest(fullUrl, body, options, method(:_onResponse));
        var last = batch[batch.size() - 1] as Array;
        System.println("[sync] envoi seq<=" + last[2] + " via " + fullUrl);
    }

    function _onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        mTimer.stop();
        mInFlight = false;
        if (responseCode == 200) {
            mErrors = 0;
            mBackoffUntilMs = 0l;
            if (data != null && data instanceof Dictionary) {
                var ack = (data as Dictionary)["lastAcceptedSequence"];
                if (ack != null) {
                    MatchStore.ackUntil(ack);
                    System.println("[sync] ack " + ack);
                }
            }
        } else {
            mErrors += 1;
            mBackoffUntilMs = System.getTimer() + mCore.nextBackoffMs(mErrors);
            System.println("[sync] erreur " + responseCode + " -> backoff");
        }
        _scheduleDrain();
    }

    // Le callback peut ne jamais être appelé (GCM endormie) — §3.8.
    function _onTimeout() as Void {
        if (mInFlight) {
            Communications.cancelAllRequests();
            _onResponse(Communications.NETWORK_REQUEST_TIMED_OUT, null);
        }
    }

    // File non vide → re-tenter au prochain créneau (≥ 5 s / backoff).
    function _scheduleDrain() as Void {
        var engine = mEngineRef;
        if (engine == null) { return; }
        var batch = mCore.batchSlice(engine.getEvents(), MatchStore.getPendingFrom(), 5);
        if (batch.size() == 0) { return; }
        var now = System.getTimer();
        var next = mLastAttemptMs + 5000l;
        if (mBackoffUntilMs > next) { next = mBackoffUntilMs; }
        var delay = next - now;
        if (delay < 1000l) { delay = 1000l; }
        mTimer.start(method(:_drain), delay, false);
    }

    function _drain() as Void {
        trigger(mEngineRef);
    }
}
