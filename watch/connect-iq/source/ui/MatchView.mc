import Toybox.Graphics;
import Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

// Écrans de l'app (mono-écran + états inline, spec §5).
module MatchScreen {
    const SETUP = 0;          // choix du format au démarrage
    const SCORE = 1;          // écran principal
    const CONFIRM_SET = 2;    // confirmation inline « terminer set ? » (DOWN=OUI BACK=NON)
    const SET_RESULT = 3;     // set terminé auto, en attente « set suivant » (DOWN)
    const MATCH_FINISHED = 4; // match terminé (DOWN = nouveau match)
    const MENU = 5;           // menu inline UP-long (Reprendre / Quitter)
}

class MatchView extends WatchUi.View {

    var mScreen = MatchScreen.SETUP;
    var mSetupIndex = 2;      // 21 POINTS par défaut
    var mMenuIndex = 0;
    var mEngine = null;

    function initialize() {
        View.initialize();
    }

    // ---- délégué -> vue (le delegate n'a aucune logique) ----

    function onSelect() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            startMatch();
            return true;
        }
        if (mScreen == MatchScreen.SCORE) {
            mEngine.pointMe();
            syncScreen();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            return menuSelect();
        }
        return true;
    }

    function onBack() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            return false;   // aucun match en cours : BACK ferme l'app (comportement CIQ naturel)
        }
        if (mScreen == MatchScreen.SCORE) {
            mEngine.pointOpponent();
            syncScreen();
            return true;    // BACK = point adversaire, ne quitte jamais (spec §3.2)
        }
        if (mScreen == MatchScreen.CONFIRM_SET) {
            mScreen = MatchScreen.SCORE;   // BACK = NON
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mScreen = MatchScreen.SCORE;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    function onUp() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            mSetupIndex = (mSetupIndex + MatchPresets.count() - 1) % MatchPresets.count();
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 1) % 2;   // liste de 2 : UP et DOWN cyclent
            WatchUi.requestUpdate();
            return true;
        }
        return true;   // UNDO = Phase 2, UP sans effet en SCORE
    }

    function onDown() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            mSetupIndex = (mSetupIndex + 1) % MatchPresets.count();
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.SCORE) {
            mScreen = MatchScreen.CONFIRM_SET;   // DOWN = changement de set -> confirmation inline
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.CONFIRM_SET) {
            mScreen = MatchScreen.SCORE;         // DOWN = OUI : sortir de la confirmation
            mEngine.changeSet();                 // leader crédité, égalité non crédité (§4.4)
            syncScreen();                        // SET_RESULT / MATCH_FINISHED / SCORE selon la phase
            return true;
        }
        if (mScreen == MatchScreen.SET_RESULT) {
            mEngine.changeSet();                 // « set suivant » (SET_FINISHED déjà enregistré)
            syncScreen();
            return true;
        }
        if (mScreen == MatchScreen.MATCH_FINISHED) {
            mScreen = MatchScreen.SETUP;         // DOWN = NOUVEAU (format mémorisé)
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 1) % 2;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    function onMenuButton() as Boolean {
        if (mScreen == MatchScreen.SCORE) {
            mScreen = MatchScreen.MENU;          // UP-long = menu inline
            mMenuIndex = 0;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    // ---- transitions ----

    function startMatch() as Void {
        mEngine = new ScoreEngine(MatchPresets.get(mSetupIndex));
        mScreen = MatchScreen.SCORE;
        WatchUi.requestUpdate();
    }

    // Après chaque mutation moteur : aligner l'écran sur la phase dérivée.
    function syncScreen() as Void {
        var p = mEngine.getPhase();
        if (p == ScorePhase.MATCH_FINISHED) {
            mScreen = MatchScreen.MATCH_FINISHED;
        } else if (p == ScorePhase.SET_RESULT) {
            mScreen = MatchScreen.SET_RESULT;
        } else if (mScreen != MatchScreen.MENU && mScreen != MatchScreen.CONFIRM_SET) {
            mScreen = MatchScreen.SCORE;
        }
        WatchUi.requestUpdate();
    }

    function menuSelect() as Boolean {
        if (mMenuIndex == 1) {
            System.exit();
        } else {
            mScreen = MatchScreen.SCORE;   // Reprendre
            WatchUi.requestUpdate();
        }
        return true;
    }

    // ---- rendu ----

    function onUpdate(dc as Dc) as Void {
        // Fond opaque AVANT clear() — sinon les frames s'accumulent (leçon Phase 0).
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var w = dc.getWidth();
        var h = dc.getHeight();
        switch (mScreen) {
        case MatchScreen.SETUP:
            drawSetup(dc, w, h);
            break;
        case MatchScreen.SCORE:
            drawScore(dc, w, h);
            break;
        case MatchScreen.CONFIRM_SET:
            drawConfirmSet(dc, w, h);
            break;
        case MatchScreen.SET_RESULT:
            drawSetResult(dc, w, h);
            break;
        case MatchScreen.MATCH_FINISHED:
            drawMatchFinished(dc, w, h);
            break;
        case MatchScreen.MENU:
            drawMenu(dc, w, h);
            break;
        }
    }

    function drawSetup(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "FORMAT", Graphics.TEXT_JUSTIFY_CENTER);
        var y = h / 2 - (3 * fMedium / 2);
        for (var i = 0; i < MatchPresets.count(); i += 1) {
            var marker = (i == mSetupIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + MatchPresets.label(i), Graphics.TEXT_JUSTIFY_CENTER);
            y += 3 * fMedium / 2;
        }
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "START = OK", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawScore(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 4, h / 2 + fLarge, Graphics.FONT_SMALL, "MOI", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(3 * w / 4, h / 2 + fLarge, Graphics.FONT_SMALL, "LUI", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY,
            MatchPresets.label(mSetupIndex) + "  SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawConfirmSet(dc as Dc, w as Number, h as Number) as Void {
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "TERMINER SET " + mEngine.getSetNumber() + " ?", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 3 * h / 4, Graphics.FONT_SMALL, "DOWN=OUI  BACK=NON", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSetResult(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber() + " TERMINE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getLastSetScoreMe() + " - " + mEngine.getLastSetScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 + fLarge, Graphics.FONT_SMALL,
            "SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "DOWN = SET SUIV.", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawMatchFinished(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "MATCH TERMINE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getSetsMe() + " - " + mEngine.getSetsOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        var winner = (mEngine.getSetsMe() > mEngine.getSetsOpp()) ? "MOI GAGNE" : "LUI GAGNE";
        dc.drawText(w / 2, h / 2 + fLarge, Graphics.FONT_SMALL, winner, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "DOWN = NOUVEAU", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawMenu(dc as Dc, w as Number, h as Number) as Void {
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "MENU", Graphics.TEXT_JUSTIFY_CENTER);
        var items = ["REPRENDRE", "QUITTER"];
        var y = h / 2 - fMedium;
        for (var i = 0; i < items.size(); i += 1) {
            var marker = (i == mMenuIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + items[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += 3 * fMedium / 2;
        }
    }
}
