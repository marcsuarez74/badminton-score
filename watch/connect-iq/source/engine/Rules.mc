import Toybox.Lang;

// Formule de fin de set (spec §4.2) — isolée du moteur pour être testée isolément.
module Rules {

    // Le set est gagné dès que le leader a >= targetScore ET
    // (écart >= winBy OU (cap > 0 ET leader >= cap)).
    function isSetOver(config as MatchConfig, scoreMe as Number, scoreOpp as Number) as Boolean {
        var high = (scoreMe >= scoreOpp) ? scoreMe : scoreOpp;
        var low = (scoreMe >= scoreOpp) ? scoreOpp : scoreMe;
        if (high < config.mTargetScore) { return false; }
        if (high - low >= config.mWinBy) { return true; }
        if (config.mCap > 0 && high >= config.mCap) { return true; }
        return false;
    }
}
