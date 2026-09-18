import Toybox.Graphics;
import Toybox.Lang;
using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

class ButtonTestView extends WatchUi.View {

    var mMode = 0;                 // 0 = test screen, 1 = inline menu
    var mMenuIndex = 0;
    var mLastEvent = "AUCUN";
    var mCount = 0;
    var mHistory = [];
    var mHistCap = 2;
    var mMenuItems = ["CONTINUER", "QUITTER"];

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var cap = (dc.getHeight() / 2 - 40) / 18;
        if (cap > 6) { cap = 6; }
        if (cap < 2) { cap = 2; }
        mHistCap = cap;
    }

    function record(label as String) as Void {
        mLastEvent = label;
        mCount = mCount + 1;
        pushHistory(mCount + ": " + label);
        WatchUi.requestUpdate();
    }

    function openMenu() as Void {
        mMode = 1;
        mMenuIndex = 0;
        WatchUi.requestUpdate();
    }

    function closeMenu() as Void {
        mMode = 0;
        WatchUi.requestUpdate();
    }

    function menuSelect() as Boolean {
        if (mMenuIndex == 1) {
            System.exit();
            return true;
        }
        closeMenu();
        return true;
    }

    function menuUp() as Boolean {
        mMenuIndex = (mMenuIndex + mMenuItems.size() - 1) % mMenuItems.size();
        WatchUi.requestUpdate();
        return true;
    }

    function menuDown() as Boolean {
        mMenuIndex = (mMenuIndex + 1) % mMenuItems.size();
        WatchUi.requestUpdate();
        return true;
    }

    function pushHistory(s as String) as Void {
        if (mHistory.size() >= mHistCap) {
            var next = [];
            for (var i = 1; i < mHistory.size(); i += 1) {
                next.add(mHistory[i]);
            }
            mHistory = next;
        }
        mHistory.add(s);
    }

    function onUpdate(dc as Dc) as Void {
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Graphics.FONT_SMALL, "BUTTON TEST", Graphics.TEXT_JUSTIFY_CENTER);
        if (mMode == 1) {
            dc.drawText(w / 2, h / 4, Graphics.FONT_MEDIUM, "MENU", Graphics.TEXT_JUSTIFY_CENTER);
            var y = h / 2 - 10;
            for (var i = 0; i < mMenuItems.size(); i += 1) {
                var marker = (i == mMenuIndex) ? "> " : "  ";
                dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + mMenuItems[i], Graphics.TEXT_JUSTIFY_CENTER);
                y += 30;
            }
            return;
        }
        dc.drawText(w / 2, h / 2 - 40, Graphics.FONT_LARGE, mLastEvent, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_MEDIUM, "N=" + mCount, Graphics.TEXT_JUSTIFY_CENTER);
        var y2 = h / 2 + 20 + dc.getFontHeight(Graphics.FONT_MEDIUM) + 6;
        for (var j = 0; j < mHistory.size() && j < mHistCap; j += 1) {
            dc.drawText(w / 2, y2 + j * 18, Graphics.FONT_TINY, mHistory[j], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
