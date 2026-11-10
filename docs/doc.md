# Project Overview

The Garmin Connect IQ companion app SalarmWatch has been implemented, validated, and compiled for all three target devices
(Forerunner 165, Forerunner 265s, and Forerunner 970) using Connect IQ SDK 9.2.0 and API level 5.2.0 (with strict type-
checking -l 3).

---

## Project Structure & File Links

- **`manifest.xml`**: Application manifest declaring minApiLevel="5.2.0", Communications permission, launcher icon, and
device targets (fr165, fr265s, fr970).

- **`monkey.jungle`**: Jungle build configuration linking manifest.xml.

- **`resources/drawables/drawables.xml`**: Launcher icon resource definition.

- **`resources/strings/strings.xml`**: App name strings.

- **`source/SalarmWatchApp.mc`**: Lifecycle management, phone message callback registration via Communications.
registerForPhoneAppMessages(), and startup sync ping.

- **`source/SalarmModel.mc`**: State machine (STATE_IDLE, STATE_UPCOMING, STATE_RINGING, STATE_ACTION_PENDING,
STATE_ACTION_CONFIRMED, STATE_ACTION_FAILED), payload validator, 10s request timeout tracker, and deduplication engine.

- **`source/SalarmWatchView.mc`**: Minimalist, AMOLED-optimized UI:

  - 36-segment perimeter ring (dark blue at bottom 270°, light sky blue at top 90°).

  - Smooth sun orbiting along the perimeter ring based on local time of day (midnight at bottom, noon at top).

  - Large countdown formatted as X:XX or XX:XX, driven by an internal 1Hz timer using local device time.

  - Subtitle formatted strictly as To [Event].

  - Fallback state when no upcoming alarm exists (--:--, No Upcoming Alarm, phone connection indicator).

  - High-contrast ringing screen with prominent Snooze and Dismiss buttons.

  - Overlays for pending confirmation, confirmed success, and failed action retry.

- **`source/SalarmWatchDelegate.mc`**: Dual touch & physical button handling (touch hitboxes, Select button for Snooze,
Back/Down button for Dismiss) with back-button interception during active ringing to prevent accidental alarm dismissal.

- **`source/SalarmAlertManager.mc`**: Safe vibration patterns (Attention.VibeProfile), tone alerts (Attention.
playTone(Attention.TONE_ALARM)), and backlight control.

- **`source/SalarmCommListener.mc`**: BLE transmission completion & error listener.

- **`source/SalarmTests.mc`**: Unit test suite covering message parsing, state transitions, array-wrapping, and error
recovery.

---

## Communication Protocol Specification

All communications between the Android app and Garmin watch app use the Garmin Connect IQ Mobile SDK:

- Phone → Watch: ConnectIQ.sendMessage(device, app, payload, callback) → delivered to watch via Communications.
registerForPhoneAppMessages().

- Watch → Phone: Communications.transmit(payload, null, listener) → delivered to Android via IQApplicationEventListener.
onMessageReceived().

### 1. Android → Watch Message Schema

Messages sent from Android should be a Map<String, Object> (which Garmin translates to a Monkey C Dictionary).

#### A. State Update (ALARM_UPDATE)

Sent when an alarm is scheduled, edited, snoozed, or when the phone responds to the watch's initial sync request:

    {
      "type": "ALARM_UPDATE",
      "id": "alarm_101",
      "title": "Morning Run",
      "state": "upcoming",
      "triggerTime": 1776582000,
      "snoozeDuration": 540
    }

- type (String): "ALARM_UPDATE".

- id (String or Number): Unique alarm identifier.

- title (String): Event label (e.g., "Morning Run"). Watch displays this as "To Morning Run".

- state (String): "upcoming", "snoozed", "ringing", or "idle".

- triggerTime (Number or Long): Unix epoch timestamp in UTC seconds when the alarm is set to fire.

- snoozeDuration (Number): Snooze length in seconds (e.g. 540 for 9 minutes).

#### B. Active Alarm Trigger (ALARM_TRIGGER)

Sent when the Android alarm fires and begins ringing:

    {
      "type": "ALARM_TRIGGER",
      "id": "alarm_101",
      "title": "Morning Run",
      "snoozeDuration": 540
    }

- Puts the watch immediately into STATE_RINGING, triggering repeating vibration pulses, audible tones, and turning on the backlight.

#### C. Action Confirmation (ACTION_CONFIRM)

Sent when the phone has successfully processed the watch's Snooze or Dismiss request:

    {
      "type": "ACTION_CONFIRM",
      "action": "snooze",
      "id": "alarm_101",
      "requestId": "req_snooze_1776582005",
      "triggerTime": 1776582540
    }

- action (String): "snooze" or "dismiss".

- requestId (String): The matching request token sent by the watch.

- triggerTime (Number, optional): The new trigger timestamp if snoozed.

- Note: The watch will not display the action as successful until this confirmation is received.

#### D. Action Rejection (ACTION_REJECT)

Sent if the phone could not execute the action (e.g., alarm was already cancelled on the phone):

    {
      "type": "ACTION_REJECT",
      "action": "snooze",
      "id": "alarm_101",
      "requestId": "req_snooze_1776582005",
      "message": "Alarm already stopped on phone"
    }

#### E. Clear Alarm (CLEAR)

Sent when an alarm is deleted or all alarms are turned off:

    {
      "type": "CLEAR"
    }

---

### 2. Watch → Android Action Schema

When the user taps or presses Snooze or Dismiss, the watch transmits the following dictionary payload:

#### A. Snooze Request

    {
      "action": "snooze",
      "alarmId": "alarm_101",
      "requestId": "req_snooze_1776582005",
      "timestamp": 1776582005,
      "snoozeDuration": 540
    }

#### B. Dismiss Request

    {
      "action": "dismiss",
      "alarmId": "alarm_101",
      "requestId": "req_dismiss_1776582012",
      "timestamp": 1776582012
    }

#### C. Initial State Sync Request

Sent automatically when the watch app opens:

    {
      "action": "sync",
      "timestamp": 1776581900
    }

In Android, this payload arrives inside the List<Object> messageData parameter of IQApplicationEventListener.onMessageReceived(). Extract the map via (Map<String, Object>) messageData.get(0).

---

## Critical Limitations & Required Android Companion Behavior

> ### Warning
>
> Garmin Watch Apps Cannot Run Continuously in the Background
>
> 1. No Background Execution: A Garmin watch-app terminates when the user returns to the watch face or when the screen times out. A terminated watch app cannot listen on a BLE socket or silently receive sendMessage() calls.
>
> 2. Waking the Watch App When an Alarm Rings:
> To make the watch ring in sync with an Android alarm when the user is not actively inside SalarmWatch, the Android app must invoke:
>
> ```mc
> connectIQ.openApplication(device, app, new IQOpenApplicationListener() {
> @Override
> public void onOpenApplicationResponse(IQDevice device, IQApp app, IQOpenApplicationStatus status) {
> // PROMPT_SHOWN_ON_DEVICE or APP_IS_ALREADY_RUNNING
> }
> });
> On Connect IQ devices, openApplication() presents a system prompt or directly launches the app. Once opened, the watch immediately sends { "action": "sync" }, and the phone can then deliver the ALARM_TRIGGER payload.
> ```
>
> 3. Garmin Connect Mobile (GCM) Must Be Running: All communication between Android and the Garmin watch routes through the Garmin Connect Mobile background service. If GCM is force-killed or battery-optimized by Android OS, communication will fail.
>
> 4. Delivery Guarantees: BLE transmissions can drop if the watch moves out of range. The watch app implements a 10-second timeout with retry states and never assumes an action succeeded without explicit ACTION_CONFIRM.

---

## Instructions for Testing in the Connect IQ Simulator

### Method 1: Testing with an Android Device via ADB Bridge (Recommended by Garmin)

1. Connect your Android phone to your PC via USB with USB Debugging enabled.
2. In your Android app build, configure ConnectIQ to use the ADB simulator protocol:
   ConnectIQ connectIQ = ConnectIQ.getInstance(context, IQConnectType.TETHERED);

3. Forward the ADB port in a terminal:
   adb forward tcp:7381 tcp:7381

4. Start the Connect IQ Simulator:
   ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/connectiq

5. In the simulator menu, select Connection → Start (or Ctrl+F1).
6. Run the compiled app:
   ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeydo bin/SalarmWatch_fr165.prg fr165

### Method 2: Simulator GUI Simulation Menu

1. In the Connect IQ Simulator window, navigate to Simulation → Communications.
2. Set the connection status to Connected.
3. Send a simulated JSON/Dictionary payload into the app mailbox to test each state transition (ALARM_UPDATE, ALARM_TRIGGER,
   ACTION_CONFIRM).
   ---

## Step-by-Step Build Guide

All binaries are compiled in the directory:

    cd /home/hzaman/Programs/GarminApp/Salarm

    # 1. Compile for Forerunner 165
    ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc \
      -l 3 -o bin/SalarmWatch_fr165.prg -f monkey.jungle -y developer_key -d fr165

    # 2. Compile for Forerunner 265s
    ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc \
      -l 3 -o bin/SalarmWatch_fr265s.prg -f monkey.jungle -y developer_key -d fr265s

    # 3. Compile for Forerunner 970
    ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc \
      -l 3 -o bin/SalarmWatch_fr970.prg -f monkey.jungle -y developer_key -d fr970

    # 4. Run unit tests
    ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc \
      -t -l 3 -o bin/SalarmWatch_test.prg -f monkey.jungle -y developer_key -d fr165

    # 5. Build full Connect IQ package (.iq file for sideloading/store)
    ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc \
      -e -l 3 -o bin/SalarmWatch.iq -f monkey.jungle -y developer_key

All commands build successfully with zero errors across all three target devices.
