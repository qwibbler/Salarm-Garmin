import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

//! Main view rendering the perimeter ring, moving sun, countdown, and alarm screens
class SalarmWatchView extends WatchUi.View {

    private var _model as SalarmModel;
    private var _uiTimer as Timer.Timer?;
    private var _pulseCounter as Number = 0;

    // Visual Palette
    private const COLOR_DARK_BLUE as Number  = 0x0A2540; // Night bottom
    private const COLOR_LIGHT_BLUE as Number = 0x38BDF8; // Day top
    private const COLOR_SUN_CORE as Number   = 0xFFE043; // Bright sun disk
    private const COLOR_SUN_HALO as Number   = 0xF59E0B; // Sun outer glow
    private const COLOR_BG as Number         = 0x000000; // Deep OLED black
    private const COLOR_ALERT_RED as Number  = 0xDC2626; // Alarm / Dismiss red
    private const COLOR_ALERT_AMB as Number  = 0xD97706; // Snooze amber
    private const COLOR_ALERT_BLUE as Number = 0x0284C7; // Snooze blue
    private const COLOR_SUCCESS as Number    = 0x16A34A; // Confirmed green

    //! Constructor
    //! @param model The application state model
    public function initialize(model as SalarmModel) {
        View.initialize();
        _model = model;
        _uiTimer = new Timer.Timer();
    }

    //! Called when view is shown
    public function onShow() as Void {
        if (_uiTimer != null) {
            // 1Hz refresh for real-time countdown and sun position
            _uiTimer.start(method(:onTimerTick), 1000, true);
        }
    }

    //! Called when view is hidden
    public function onHide() as Void {
        if (_uiTimer != null) {
            _uiTimer.stop();
        }
    }

    //! Timer callback
    public function onTimerTick() as Void {
        _pulseCounter = (_pulseCounter + 1) % 60;
        WatchUi.requestUpdate();
    }

    //! Main draw function
    //! @param dc Device Context
    public function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        // Clear screen with OLED black
        dc.setColor(Graphics.COLOR_WHITE, COLOR_BG);
        dc.clear();

        var state = _model.getState();

        if (state == SalarmModel.STATE_RINGING) {
            drawRingingScreen(dc, w, h, cx, cy);
        } else {
            // Draw standard perimeter ring and moving sun
            var ringRadius = cx - 8;
            drawPerimeterRing(dc, cx, cy, ringRadius);
            drawMovingSun(dc, cx, cy, ringRadius);

            if (state == SalarmModel.STATE_UPCOMING) {
                drawUpcomingScreen(dc, w, h, cx, cy);
            } else {
                drawIdleScreen(dc, w, h, cx, cy);
            }
        }

        // Overlay states: Pending, Confirmed, Failed
        if (state == SalarmModel.STATE_ACTION_PENDING) {
            drawPendingOverlay(dc, w, h, cx, cy);
        } else if (state == SalarmModel.STATE_ACTION_CONFIRMED) {
            drawConfirmedOverlay(dc, w, h, cx, cy);
        } else if (state == SalarmModel.STATE_ACTION_FAILED) {
            drawFailedOverlay(dc, w, h, cx, cy);
        }
    }

    // -------------------------------------------------------------
    // Perimeter Ring & Sun Drawing
    // -------------------------------------------------------------

    //! Draws circular perimeter ring: dark blue at bottom (270°), light blue at top (90°)
    private function drawPerimeterRing(dc as Graphics.Dc, cx as Number, cy as Number, radius as Number) as Void {
        var penWidth = 5;
        dc.setPenWidth(penWidth);

        // Deconstruct RGB endpoints
        var rDark = (COLOR_DARK_BLUE >> 16) & 0xFF;
        var gDark = (COLOR_DARK_BLUE >> 8) & 0xFF;
        var bDark = COLOR_DARK_BLUE & 0xFF;

        var rLight = (COLOR_LIGHT_BLUE >> 16) & 0xFF;
        var gLight = (COLOR_LIGHT_BLUE >> 8) & 0xFF;
        var bLight = COLOR_LIGHT_BLUE & 0xFF;

        // Draw 36 arc segments (10 degrees each)
        var segments = 36;
        var step = 360.0 / segments;

        for (var i = 0; i < segments; i++) {
            var startDeg = i * step;
            var endDeg = (i + 1) * step;
            var midDeg = startDeg + (step / 2.0);

            // In Connect IQ: 90° is Top, 270° is Bottom
            // sin(90°) = 1 (top -> Light Blue), sin(270°) = -1 (bottom -> Dark Blue)
            var rad = Math.toRadians(midDeg);
            var sinVal = Math.sin(rad);
            var t = (sinVal + 1.0) / 2.0; // Range: 0.0 at bottom to 1.0 at top

            var r = (rDark + t * (rLight - rDark)).toNumber();
            var g = (gDark + t * (gLight - gDark)).toNumber();
            var b = (bDark + t * (bLight - bDark)).toNumber();
            var segColor = (r << 16) | (g << 8) | b;

            dc.setColor(segColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, startDeg.toNumber(), endDeg.toNumber() + 1);
        }
    }

    //! Draws small sun moving around ring according to local time of day
    private function drawMovingSun(dc as Graphics.Dc, cx as Number, cy as Number, radius as Number) as Void {
        var clockTime = System.getClockTime();
        var totalSeconds = clockTime.hour * 3600 + clockTime.min * 60 + clockTime.sec;
        var dayFraction = totalSeconds.toFloat() / 86400.0;

        // At midnight (0:00) -> 270° (Bottom)
        // At 6:00 AM (0.25) -> 180° (Left)
        // At 12:00 PM (0.50) -> 90° (Top)
        // At 6:00 PM (0.75) -> 0° (Right)
        var sunAngleDeg = 270.0 - (dayFraction * 360.0);
        var sunRad = Math.toRadians(sunAngleDeg);

        var sunX = cx + (radius * Math.cos(sunRad)).toNumber();
        var sunY = cy - (radius * Math.sin(sunRad)).toNumber(); // CIQ Y increases downwards

        // Outer glow
        dc.setColor(COLOR_SUN_HALO, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sunX, sunY, 7);

        // Bright sun core
        dc.setColor(COLOR_SUN_CORE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sunX, sunY, 4);
    }

    // -------------------------------------------------------------
    // Upcoming Alarm Screen
    // -------------------------------------------------------------

    //! Renders upcoming alarm countdown and event subtitle
    private function drawUpcomingScreen(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        var trigger = _model.getTriggerTime();
        var now = Time.now().value();
        var diff = trigger - now;

        var countdownStr = "0:00";
        if (diff > 0) {
            if (diff >= 3600) {
                var hours = diff / 3600;
                var mins = (diff % 3600) / 60;
                countdownStr = Lang.format("$1$:$2$", [hours, mins.format("%02d")]);
            } else {
                var mins = diff / 60;
                var secs = diff % 60;
                countdownStr = Lang.format("$1$:$2$", [mins, secs.format("%02d")]);
            }
        }

        // Subtitle formatted strictly as "To [Event]"
        var eventTitle = _model.getTitle();
        var subtitle = "To " + eventTitle;

        // Top Status pill: Next Alarm trigger time
        var triggerMoment = new Time.Moment(trigger);
        var trigInfo = Gregorian.info(triggerMoment, Time.FORMAT_SHORT);
        var trigTimeStr = Lang.format("$1$:$2$", [trigInfo.hour.format("%02d"), trigInfo.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.28).toNumber(), Graphics.FONT_XTINY, "ALARM AT " + trigTimeStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Large Countdown (X:XX or XX:XX)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.08).toNumber(), Graphics.FONT_NUMBER_HOT, countdownStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Subtitle "To [Event]"
        dc.setColor(COLOR_LIGHT_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.16).toNumber(), Graphics.FONT_SMALL, subtitle, Graphics.TEXT_JUSTIFY_CENTER);

        // Connection hint
        drawConnectionIndicator(dc, cx, (cy + (h * 0.32)).toNumber());
    }

    // -------------------------------------------------------------
    // Idle / Fallback Screen (No upcoming alarm)
    // -------------------------------------------------------------

    private function drawIdleScreen(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        // Fallback header
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.26).toNumber(), Graphics.FONT_XTINY, "SALARM COMPANION", Graphics.TEXT_JUSTIFY_CENTER);

        // Fallback placeholder time
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.06).toNumber(), Graphics.FONT_NUMBER_HOT, "--:--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Fallback subtitle
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.16).toNumber(), Graphics.FONT_TINY, "No Upcoming Alarm", Graphics.TEXT_JUSTIFY_CENTER);

        // Connection status
        drawConnectionIndicator(dc, cx, (cy + (h * 0.28)).toNumber());
    }

    private function drawConnectionIndicator(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var connected = _model.isPhoneConnected();
        var dotColor = connected ? COLOR_SUCCESS : COLOR_ALERT_RED;
        var text = connected ? "Phone Connected" : "Waiting for Phone";

        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 52, y + 8, 3);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 5, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------
    // High-Contrast Active Alarm Screen (Ringing)
    // -------------------------------------------------------------

    private function drawRingingScreen(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        // High contrast pulsating background border
        var pulseColor = (_pulseCounter % 2 == 0) ? COLOR_ALERT_RED : COLOR_ALERT_AMB;
        dc.setPenWidth(6);
        dc.setColor(pulseColor, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 4);

        // Top Banner: ALARM RINGING
        dc.setColor(pulseColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((cx - (w * 0.38)).toNumber(), (h * 0.08).toNumber(), (w * 0.76).toNumber(), (h * 0.10).toNumber(), 6);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.13).toNumber(), Graphics.FONT_TINY, "! ALARM RINGING !", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Event Title & Current Time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.25).toNumber(), Graphics.FONT_MEDIUM, _model.getTitle(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.36).toNumber(), Graphics.FONT_SMALL, timeStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // SNOOZE BUTTON (Large Upper-Middle Control)
        var snoozeRect = getSnoozeButtonRect(w, h);
        dc.setColor(COLOR_ALERT_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(snoozeRect[0], snoozeRect[1], snoozeRect[2], snoozeRect[3], 12);

        // Snooze border for high visibility
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(snoozeRect[0], snoozeRect[1], snoozeRect[2], snoozeRect[3], 12);

        var snoozeMins = _model.getSnoozeDuration() / 60;
        var snoozeLabel = Lang.format("SNOOZE (+$1$m)", [snoozeMins]);
        dc.drawText(cx, snoozeRect[1] + (snoozeRect[3] / 2) - 8, Graphics.FONT_SMALL, snoozeLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_LIGHT_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, snoozeRect[1] + (snoozeRect[3] / 2) + 12, Graphics.FONT_XTINY, "[SELECT BUTTON]", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // DISMISS BUTTON (Large Lower Control)
        var dismissRect = getDismissButtonRect(w, h);
        dc.setColor(COLOR_ALERT_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(dismissRect[0], dismissRect[1], dismissRect[2], dismissRect[3], 12);

        // Dismiss border
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(dismissRect[0], dismissRect[1], dismissRect[2], dismissRect[3], 12);

        dc.drawText(cx, dismissRect[1] + (dismissRect[3] / 2) - 8, Graphics.FONT_SMALL, "DISMISS", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dismissRect[1] + (dismissRect[3] / 2) + 12, Graphics.FONT_XTINY, "[BACK BUTTON]", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // -------------------------------------------------------------
    // Overlays for Asynchronous Phone Confirmation
    // -------------------------------------------------------------

    private function drawPendingOverlay(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        // Semi-opaque background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, cx - 10);

        dc.setPenWidth(3);
        dc.setColor(COLOR_LIGHT_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 10);

        var actionName = (_model.getPendingAction() == SalarmModel.ACTION_SNOOZE) ? "Snoozing..." : "Dismissing...";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 35, Graphics.FONT_MEDIUM, actionName, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 5, Graphics.FONT_TINY, "Waiting for Phone...", Graphics.TEXT_JUSTIFY_CENTER);

        // Animated dot indicator
        var dots = "";
        var count = (_pulseCounter % 4);
        for (var i = 0; i < count; i++) {
            dots = dots + " •";
        }
        dc.setColor(COLOR_LIGHT_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 30, Graphics.FONT_LARGE, dots, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawConfirmedOverlay(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, cx - 10);

        dc.setPenWidth(4);
        dc.setColor(COLOR_SUCCESS, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 10);

        dc.setColor(COLOR_SUCCESS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 25, Graphics.FONT_MEDIUM, "CONFIRMED", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Graphics.FONT_SMALL, _model.getStatusText(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawFailedOverlay(dc as Graphics.Dc, w as Number, h as Number, cx as Number, cy as Number) as Void {
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, cx - 10);

        dc.setPenWidth(4);
        dc.setColor(COLOR_ALERT_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 10);

        dc.setColor(COLOR_ALERT_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 40, Graphics.FONT_TINY, "ACTION NOT CONFIRMED", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 15, Graphics.FONT_XTINY, _model.getStatusText(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_ALERT_AMB, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - (w * 0.32), cy + 15, (w * 0.64), 30, 8);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 30, Graphics.FONT_XTINY, "TAP TO RETRY", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // -------------------------------------------------------------
    // Button Bounds Helpers (for touch input)
    // -------------------------------------------------------------

    public static function getSnoozeButtonRect(w as Number, h as Number) as Array<Number> {
        var bw = (w * 0.76).toNumber();
        var bh = (h * 0.17).toNumber();
        var bx = (w - bw) / 2;
        var by = (h * 0.46).toNumber();
        return [bx, by, bw, bh];
    }

    public static function getDismissButtonRect(w as Number, h as Number) as Array<Number> {
        var bw = (w * 0.76).toNumber();
        var bh = (h * 0.17).toNumber();
        var bx = (w - bw) / 2;
        var by = (h * 0.68).toNumber();
        return [bx, by, bw, bh];
    }
}
