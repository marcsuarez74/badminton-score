import Toybox.Lang;

// Moteur de score PUR (aucun import Graphics/WatchUi, spec §6.2).
// Event-sourcing : l'état est le replay du journal ; les mutations poussent
// des événements puis rejouent. L'undo (Phase 2) retirera le dernier event.
class ScoreEngine {

    var mConfig;      // MatchConfig
    var mEvents;      // Array de tableaux positionnels

    // État dérivé (replay)
    var mPhase;             // ScorePhase.PLAYING / SET_RESULT / MATCH_FINISHED
    var mScoreMe;           // set courant
    var mScoreOpp;
    var mSetsMe;            // sets gagnés
    var mSetsOpp;
    var mSetNumber;         // 1-based
    var mLastSetScoreMe;    // score final du dernier set terminé (SET_RESULT)
    var mLastSetScoreOpp;

    function initialize(config) {
        mConfig = config;
        mEvents = [];
        replay();
    }

    // ---- mutations ----

    function pointMe() as Void {
        if (mPhase != ScorePhase.PLAYING) { return; }
        appendEvent([ScoreEvent.TYPE_POINT_ME]);
        checkAutoSetFinish(0);
    }

    function pointOpponent() as Void {
        if (mPhase != ScorePhase.PLAYING) { return; }
        appendEvent([ScoreEvent.TYPE_POINT_OPPONENT]);
        checkAutoSetFinish(1);
    }

    // Transition « set suivant » : depuis SET_RESULT (fin auto, set déjà crédité)
    // ou depuis PLAYING (changement manuel confirmé — leader strict crédité, §4.4).
    function changeSet() as Void {
        if (mPhase == ScorePhase.MATCH_FINISHED) { return; }
        var winner = -1;
        if (mPhase == ScorePhase.PLAYING) {
            if (mScoreMe > mScoreOpp) { winner = 0; }
            else if (mScoreOpp > mScoreMe) { winner = 1; }
        }
        appendEvent([ScoreEvent.TYPE_SET_CHANGED, winner]);
        if (mPhase == ScorePhase.MATCH_FINISHED) {
            appendEvent([ScoreEvent.TYPE_MATCH_FINISHED]);
        }
    }

    // Nouveau match (menu Réinitialiser ou DOWN sur MATCH_FINISHED).
    function newMatch(config) as Void {
        mConfig = config;
        mEvents = [];
        replay();
    }

    // ---- journal + replay ----

    function appendEvent(e) as Void {
        mEvents.add(e);
        replay();
    }

    function replay() as Void {
        mPhase = ScorePhase.PLAYING;
        mScoreMe = 0;
        mScoreOpp = 0;
        mSetsMe = 0;
        mSetsOpp = 0;
        mSetNumber = 1;
        mLastSetScoreMe = 0;
        mLastSetScoreOpp = 0;
        for (var i = 0; i < mEvents.size(); i += 1) {
            applyEvent(mEvents[i]);
        }
    }

    function applyEvent(e) as Void {
        switch (e[0]) {
        case ScoreEvent.TYPE_POINT_ME:
            mScoreMe += 1;
            break;
        case ScoreEvent.TYPE_POINT_OPPONENT:
            mScoreOpp += 1;
            break;
        case ScoreEvent.TYPE_SET_FINISHED:
            mLastSetScoreMe = mScoreMe;
            mLastSetScoreOpp = mScoreOpp;
            if (e[1] == 0) { mSetsMe += 1; } else { mSetsOpp += 1; }
            if (mSetsMe >= mConfig.mSetsToWin || mSetsOpp >= mConfig.mSetsToWin) {
                mPhase = ScorePhase.MATCH_FINISHED;
            } else {
                mPhase = ScorePhase.SET_RESULT;
            }
            break;
        case ScoreEvent.TYPE_SET_CHANGED:
            if (e[1] == 0) { mSetsMe += 1; }
            else if (e[1] == 1) { mSetsOpp += 1; }
            mSetNumber += 1;
            mScoreMe = 0;
            mScoreOpp = 0;
            if (mSetsMe >= mConfig.mSetsToWin || mSetsOpp >= mConfig.mSetsToWin) {
                mPhase = ScorePhase.MATCH_FINISHED;
            } else {
                mPhase = ScorePhase.PLAYING;
            }
            break;
        case ScoreEvent.TYPE_MATCH_FINISHED:
            mPhase = ScorePhase.MATCH_FINISHED;
            break;
        }
    }

    // Fin de set automatique après un point : pousse SET_FINISHED puis,
    // si le match est gagné, MATCH_FINISHED (verrou §4.5).
    function checkAutoSetFinish(winner as Number) as Void {
        if (!Rules.isSetOver(mConfig, mScoreMe, mScoreOpp)) { return; }
        appendEvent([ScoreEvent.TYPE_SET_FINISHED, winner]);
        if (mPhase == ScorePhase.MATCH_FINISHED) {
            appendEvent([ScoreEvent.TYPE_MATCH_FINISHED]);
        }
    }

    // ---- lectures pour l'UI ----

    function getPhase() as Number { return mPhase; }
    function getScoreMe() as Number { return mScoreMe; }
    function getScoreOpp() as Number { return mScoreOpp; }
    function getSetsMe() as Number { return mSetsMe; }
    function getSetsOpp() as Number { return mSetsOpp; }
    function getSetNumber() as Number { return mSetNumber; }
    function getLastSetScoreMe() as Number { return mLastSetScoreMe; }
    function getLastSetScoreOpp() as Number { return mLastSetScoreOpp; }
    function getConfig() as MatchConfig { return mConfig; }
    function getEvents() as Array { return mEvents; }
}
