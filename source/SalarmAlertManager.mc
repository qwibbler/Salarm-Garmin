import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Handles alarm vibration, audio tones, and screen backlight alerts
class SalarmAlertManager {

    private var _alertTimer as Timer.Timer?;
    private var _isAlerting as Boolean = false;

    // Repeating pulse interval (milliseconُds)
    private const PULSE_INTERVAL_MS as Number = 1800;

    //! Constructor
    public function initialize() {
        _alertTimer = new Timer.Timer();
    }

    //! Start active alerting (vibration + tone + backlight)
    public function startAlert() as Void {
        if (_isAlerting) {
            return;
        }
        _isAlerting = true;
        pulse(); // Immediate first alert

        if (_alertTimer != null) {
            _alertTimer.start(method(:onAlertTimerTick), PULSE_INTERVAL_MS, true);
        }
    }

    //! Stop active alerting
    public function stopAlert() as Void {
        _isAlerting = false;
        if (_alertTimer != null) {
            _alertTimer.stop();
        }
    }

    //! Check if currently alerting
    public function isAlerting() as Boolean {
        return _isAlerting;
    }

    //! Timer callback for repeating pulses
    public function onAlertTimerTick() as Void {
        if (_isAlerting) {
            pulse();
        }
    }

    //! Triggers a single pulse of vibration, tone, and backlight safely
    public function pulse() as Void {
        // Backlight activation
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                System.println("[SalarmAlert] Backlight error: " + e.getErrorMessage());
            }
        }

        // Audio tone
        if (Attention has :playTone) {
            try {
                Attention.playTone(Attention.TONE_ALARM);
            } catch (e) {
                System.println("[SalarmAlert] Tone error: " + e.getErrorMessage());
            }
        }

        // Vibration pattern
        if (Attention has :vibrate) {
            try {
                var vibePattern = [
                    new Attention.VibeProfile(70, 200),
                    new Attention.VibeProfile(0, 100),
                    new Attention.VibeProfile(100, 350),
                    new Attention.VibeProfile(0, 100),
                    new Attention.VibeProfile(100, 350)
                ];
                Attention.vibrate(vibePattern);
            } catch (e) {
                System.println("[SalarmAlert] Vibrate error: " + e.getErrorMessage());
            }
        }
    }
}
