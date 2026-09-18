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
    const MENU = 5;           // menu inline UP-long (Reprendre / Format / Reset / Quitter)
}

class MatchView extends WatchUi.View {

    var mScreen = MatchScreen.SETUP;
    var mSetupIndex = 2;      // 21 POINTS par défaut
    var mMenuIndex = 0;
    var mEngine = null;
    var mMatchId = "";        // id du match courant (protocole §7.1)

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
            if (mEngine != null) {          // match existant (menu FORMAT / fin de match) : BACK = annuler
                syncScreen();               // retour SCORE / SET_RESULT / MATCH_FINISHED selon la phase
                return true;
            }
            return false;                   // pré-match : BACK ferme l'app (comportement CIQ naturel, Phase 1)
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
            mMenuIndex = (mMenuIndex + 3) % 4;   // UP : recule dans la liste de 4
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.SCORE || mScreen == MatchScreen.SET_RESULT) {
            mEngine.undo();              // UP = UNDO (§3.2/D7) — depuis SCORE et SET_RESULT
            syncScreen();                // set repris → SCORE ; undo SET_CHANGED → SET_RESULT
            return true;
        }
        return true;
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
            mMenuIndex = (mMenuIndex + 1) % 4;
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
        mMatchId = genMatchId();
        mEngine = new ScoreEngine(MatchPresets.get(mSetupIndex), mMatchId);
        mScreen = MatchScreen.SCORE;
        WatchUi.requestUpdate();
    }

    // Id de match : ms depuis le boot — suffit en local ; le backend
    // l'espacera du deviceId en Phase 4a (§8.2 : id = matchId:sequence).
    function genMatchId() as String {
        return System.getTimer().toString();
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

    // Menu inline §5 : Reprendre / Changer de format / Réinitialiser / Quitter.
    // (Labels compacts « FORMAT »/« RESET » : écrans ronds, leçon Phase 1.)
    function menuSelect() as Boolean {
        if (mMenuIndex == 0) {
            mScreen = MatchScreen.SCORE;      // Reprendre
            WatchUi.requestUpdate();
        } else if (mMenuIndex == 1) {
            mScreen = MatchScreen.SETUP;      // Changer de format (START = nouveau match)
            WatchUi.requestUpdate();
        } else if (mMenuIndex == 2) {
            mEngine.newMatch(mEngine.getConfig(), genMatchId());   // Réinitialiser
            mScreen = MatchScreen.SCORE;
            WatchUi.requestUpdate();
        } else {
            System.exit();                    // Quitter — dernier bloc, rien après
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

    // Ligne d'aide du bas : FONT_SMALL si le texte tient, FONT_TINY sinon.
    // Bas du texte à h*7/8 : sur écran ROND, tout ce qui descend plus bas
    // déborde du cercle (corde quasi nulle au bas) — leçon Task 6 simu.
    function drawFooter(dc as Dc, w as Number, h as Number, text as String) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var y = h * 7 / 8 - fSmall;
        if (dc.getTextWidthInPixels(text, Graphics.FONT_SMALL) > w * 2 / 3) {
            dc.drawText(w / 2, y, Graphics.FONT_TINY, text, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(w / 2, y, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Position de la sous-ligne sous le gros score : jamais sous le footer.
    // (min entre la position naturelle h/2+fLarge et le haut du footer —
    // sinon chevauchement sur les petits écrans, constaté instinct2/fr55.)
    function subLineY(h as Number, fLarge as Number, fSmall as Number) as Number {
        var footerTop = h * 7 / 8 - fSmall;
        var y = h / 2 + fLarge;
        return (y > footerTop - fSmall) ? footerTop - fSmall : y;
    }

    function drawSetup(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "FORMAT", Graphics.TEXT_JUSTIFY_CENTER);
        var titleBottom = h / 8 + fSmall;
        var footerTop = h * 7 / 8 - fSmall;          // coherent avec drawFooter
        var zone = footerTop - titleBottom;
        var spacing = 3 * fMedium / 2;
        if (spacing * 2 + fMedium > zone) {
            spacing = (zone - fMedium) / 2;          // resserré : items entre titre et footer
            if (spacing < 1) { spacing = 1; }
        }
        var y = titleBottom + (zone - (spacing * 2 + fMedium)) / 2;
        for (var i = 0; i < MatchPresets.count(); i += 1) {
            var marker = (i == mSetupIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + MatchPresets.label(i), Graphics.TEXT_JUSTIFY_CENTER);
            y += spacing;
        }
        drawFooter(dc, w, h, "START = OK");
    }

    function drawScore(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        var ySub = subLineY(h, fLarge, fSmall);
        dc.drawText(w / 4, ySub, Graphics.FONT_SMALL, "MOI", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(3 * w / 4, ySub, Graphics.FONT_SMALL, "LUI", Graphics.TEXT_JUSTIFY_CENTER);
        drawFooter(dc, w, h,
            MatchPresets.shortLabel(mSetupIndex) + "  SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp());
    }

    function drawConfirmSet(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "TERMINER SET " + mEngine.getSetNumber() + " ?", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        // Aide sur 2 lignes : le texte complet dépasse la corde du cercle
        // même en FONT_TINY (mesures Task 6). 2 lignes courtes tiennent.
        var y2 = h * 7 / 8 - fSmall;
        dc.drawText(w / 2, y2, Graphics.FONT_SMALL, "BACK = NON", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, y2 - fSmall, Graphics.FONT_SMALL, "DOWN = OUI", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSetResult(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber() + " TERMINE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getLastSetScoreMe() + " - " + mEngine.getLastSetScoreOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, subLineY(h, fLarge, fSmall), Graphics.FONT_SMALL,
            "SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        drawFooter(dc, w, h, "DOWN = SET SUIV.");
    }

    function drawMatchFinished(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "MATCH TERMINE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getSetsMe() + " - " + mEngine.getSetsOpp(), Graphics.TEXT_JUSTIFY_CENTER);
        var winner = (mEngine.getSetsMe() > mEngine.getSetsOpp()) ? "MOI GAGNE" : "LUI GAGNE";
        dc.drawText(w / 2, subLineY(h, fLarge, fSmall), Graphics.FONT_SMALL, winner, Graphics.TEXT_JUSTIFY_CENTER);
        drawFooter(dc, w, h, "DOWN = NOUVEAU");
    }

    function drawMenu(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "MENU", Graphics.TEXT_JUSTIFY_CENTER);
        var items = ["REPRENDRE", "FORMAT", "RESET", "QUITTER"];
        var titleBottom = h / 8 + fSmall;
        var zone = h - titleBottom;                 // pas de footer sur le menu
        var spacing = 5 * fMedium / 4;
        if (spacing * 3 + fMedium > zone) {
            spacing = (zone - fMedium) / 3;         // compression (fr55)
            if (spacing < 1) { spacing = 1; }
        }
        var y = titleBottom + (zone - (spacing * 3 + fMedium)) / 2;
        for (var i = 0; i < items.size(); i += 1) {
            var marker = (i == mMenuIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + items[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += spacing;
        }
    }
}
