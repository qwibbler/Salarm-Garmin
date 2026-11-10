import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Handles touch gestures and physical button inputs for SalarmWatch
class SalarmWatchDelegate extends WatchUi.BehaviorDelegate {

    private var _model as SalarmModel;

    //! Constructor
    //! @param model Application data model
    public function initialize(model as SalarmModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    //! Handle touchscreen tap events
    //! @param evt Click event containing screen coordinates
    public function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var x = coords[0];
        var y = coords[1];

        var devSettings = System.getDeviceSettings();
        var w = devSettings.screenWidth;
        var h = devSettings.screenHeight;

        var state = _model.getState();

        if (state == SalarmModel.STATE_RINGING) {
            // Check Snooze button hitbox
            var snoozeRect = SalarmWatchView.getSnoozeButtonRect(w, h);
            if (isPointInside(x, y, snoozeRect)) {
                System.println("[SalarmDelegate] Tap: Snooze button clicked.");
                _model.requestSnooze();
                return true;
            }

            // Check Dismiss button hitbox
            var dismissRect = SalarmWatchView.getDismissButtonRect(w, h);
            if (isPointInside(x, y, dismissRect)) {
                System.println("[SalarmDelegate] Tap: Dismiss button clicked.");
                _model.requestDismiss();
                return true;
            }
        } else if (state == SalarmModel.STATE_ACTION_FAILED) {
            System.println("[SalarmDelegate] Tap: Retry or clear failed state.");
            _model.retryOrDismissFailure();
            return true;
        } else if (state == SalarmModel.STATE_IDLE || state == SalarmModel.STATE_UPCOMING) {
            // Tapping during normal screen requests a state sync from phone
            var app = Application.getApp();
            if (app has :syncWithPhone) {
                app.syncWithPhone();
            }
            return true;
        }

        return false;
    }

    //! Handle Select/Enter physical button
    public function onSelect() as Boolean {
        var state = _model.getState();

        if (state == SalarmModel.STATE_RINGING) {
            System.println("[SalarmDelegate] Select button: Requesting Snooze.");
            _model.requestSnooze();
            return true;
        } else if (state == SalarmModel.STATE_ACTION_FAILED) {
            _model.retryOrDismissFailure();
            return true;
        } else if (state == SalarmModel.STATE_IDLE || state == SalarmModel.STATE_UPCOMING) {
            var app = Application.getApp();
            if (app has :syncWithPhone) {
                app.syncWithPhone();
            }
            return true;
        }

        return false;
    }

    //! Handle Back/Lap physical button
    public function onBack() as Boolean {
        var state = _model.getState();

        if (state == SalarmModel.STATE_RINGING) {
            System.println("[SalarmDelegate] Back button: Requesting Dismiss.");
            _model.requestDismiss();
            // Return true to prevent closing the app without phone confirmation
            return true;
        } else if (state == SalarmModel.STATE_ACTION_PENDING) {
            // Do not dismiss app while request is in flight
            return true;
        } else if (state == SalarmModel.STATE_ACTION_FAILED) {
            _model.retryOrDismissFailure();
            return true;
        }

        // Return false to allow natural exit when idle or viewing upcoming alarm
        return false;
    }

    //! Handle physical key events (Up, Down, Enter, Esc)
    public function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        var state = _model.getState();

        if (state == SalarmModel.STATE_RINGING) {
            if (key == WatchUi.KEY_ENTER) {
                _model.requestSnooze();
                return true;
            } else if (key == WatchUi.KEY_DOWN || key == WatchUi.KEY_ESC) {
                _model.requestDismiss();
                return true;
            }
        }

        return false;
    }

    //! Bounding box hit test helper
    private function isPointInside(px as Number, py as Number, rect as Array<Number>) as Boolean {
        var rx = rect[0];
        var ry = rect[1];
        var rw = rect[2];
        var rh = rect[3];
        return (px >= rx && px <= (rx + rw) && py >= ry && py <= (ry + rh));
    }
}
