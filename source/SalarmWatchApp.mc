import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main application entry point for SalarmWatch
class SalarmWatchApp extends Application.AppBase {

    private var _model as SalarmModel;
    private var _alertManager as SalarmAlertManager;
    private var _view as SalarmWatchView;
    private var _delegate as SalarmWatchDelegate;

    //! Constructor
    public function initialize() {
        AppBase.initialize();

        _alertManager = new SalarmAlertManager();
        _model = new SalarmModel();
        _model.setAlertManager(_alertManager);

        _view = new SalarmWatchView(_model);
        _delegate = new SalarmWatchDelegate(_model);

        // Register for phone app messages
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneAppMessage));
        }
    }

    //! Handle app startup
    public function onStart(state as Dictionary?) as Void {
        System.println("[SalarmWatchApp] Started.");

        // Request initial synchronization from Android companion
        syncWithPhone();
    }

    //! Handle app shutdown
    public function onStop(state as Dictionary?) as Void {
        System.println("[SalarmWatchApp] Stopped.");

        if (_alertManager != null) {
            _alertManager.stopAlert();
        }

        // Unregister callback
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(null);
        }
    }

    //! Return initial view and delegate
    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [_view, _delegate];
    }

    //! Callback for incoming phone app messages
    public function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        System.println("[SalarmWatchApp] Received PhoneAppMessage.");
        if (msg != null && _model != null) {
            _model.processIncomingMessage(msg.data);
        }
        WatchUi.requestUpdate();
    }

    //! Sends a sync request to the Android app
    public function syncWithPhone() as Void {
        var payload = {
            "action" => "sync",
            "timestamp" => Time.now().value()
        };

        var listener = new SalarmCommListener(_model);
        try {
            Communications.transmit(payload, null, listener);
            System.println("[SalarmWatchApp] Sync request sent to phone.");
        } catch (e) {
            System.println("[SalarmWatchApp] Could not send sync request: " + e.getErrorMessage());
        }
    }
}
