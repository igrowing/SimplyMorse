# Privacy Policy — SimplyMorse

**Last updated: August 28, 2026**

SimplyMorse is an open-source audio-visual Morse code encoder-decoder
developed by [igrowing](https://github.com/igrowing/SimplyMorse). This
policy explains what data the app accesses, why, and what it does (and does
not) do with it.

---

## 1. Summary (TL;DR)

- SimplyMorse **does not collect, store, transmit, or share any personal
  data**.
- The app works **fully offline**. It has no network code and makes no
  Internet requests at all.
- Decoding Morse code from sound uses the **microphone**, and decoding from
  light uses the **camera**. Both run **only on the screen where you start
  them**, and the audio and video are analysed live in memory — nothing is
  ever recorded to a file, saved, or sent anywhere.
- Sending Morse code can drive the phone's **flashlight (LED)**, the
  speaker, or both. This happens only while you are on a Send screen and
  tap "Send".
- There are **no ads, no analytics, no tracking, no telemetry, no
  accounts, no crash reporting**.
- The app is **open source** — you can inspect every line of code at
  [github.com/igrowing/SimplyMorse](https://github.com/igrowing/SimplyMorse).

---

## 2. Permissions and Why They Are Used

### Microphone (RECORD_AUDIO / NSMicrophoneUsageDescription)

Used **only** on the "Hear" decoding screen, to listen for a Morse tone and
convert it to text. Audio is streamed straight into the on-device decoder
as raw samples, processed frame by frame, and discarded. It is **never**
written to storage, **never** kept after you leave the screen or tap
"Pause", and **never** transmitted.

On Android, the `record` library that provides microphone streaming also
declares `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE` in the
merged manifest. SimplyMorse does not start a foreground service and does
not listen in the background — capture stops when you pause or leave the
screen.

### Camera (CAMERA / NSCameraUsageDescription)

Used **only** on the "See" decoding screen, to watch a blinking light and
convert it to text. Frames are captured at low resolution, immediately
reduced to a small brightness map, analysed, and discarded. Audio recording
on the camera is disabled. No photo or video is ever saved or sent.

### Flashlight / LED

Sending Morse code as light toggles the device torch through the
`torch_light` library while you hold a Send screen and a transmission is
running. No location, identity, or other data is involved.

### Network

SimplyMorse requests **no** Internet permission and contains **no**
networking code. It cannot phone home even by accident.

---

## 3. What Happens On Each Screen

| Screen | What it accesses | What leaves the device |
|--------|------------------|------------------------|
| Main / Send menu | Nothing | Nothing |
| Send (Sound / Flash / Both) | Speaker and/or LED while transmitting | Nothing |
| Hear (decode audio) | Microphone stream while active | Nothing |
| See (decode light) | Camera stream while active | Nothing |

All processing is local. The only thing that can ever leave the device is
text **you** choose to send via the system share sheet (see Section 4).

---

## 4. Data Storage

SimplyMorse stores a few small settings on your device using the standard
platform key-value store (Android SharedPreferences / iOS
`NSUserDefaults`):

| What | Why |
|------|-----|
| Sending speed (words per minute) | Restore your last-used speed |
| Tone frequency (Hz) | Restore your last-used sending tone |
| Text history — the messages you have typed to send | Offer them from a drop-down next time |

The theme (light/dark/system) selection is **not** persisted; it resets to
"follow system" on each launch.

No decoded text, microphone audio, camera images, diagnostic logs, or usage
history are saved. No data is stored in the cloud. No account or
registration is required. Uninstalling the app removes all stored data.

### Sharing text

The decoder screens let you share the decoded text through your device's
standard share sheet (via the `share_plus` library). This happens only when
you tap Share and pick a destination app yourself. SimplyMorse has no
control over, and no visibility into, what the app you choose does with that
text.

---

## 5. Third-Party Services and Libraries

SimplyMorse contacts **no third-party services** of any kind.

It uses the following **open-source libraries**. None of them collect,
transmit, or process personal data. All are distributed under permissive
open-source licenses.

| Library | License | Purpose |
|---------|---------|---------|
| [Flutter](https://flutter.dev) | BSD 3-Clause | UI framework |
| [provider](https://pub.dev/packages/provider) | MIT | State management |
| [get_it](https://pub.dev/packages/get_it) | MIT | Dependency injection |
| [equatable](https://pub.dev/packages/equatable) | MIT | Value equality for domain models |
| [meta](https://pub.dev/packages/meta) | BSD 3-Clause | Source annotations |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | BSD 3-Clause | Local storage of speed, tone and text history |
| [audioplayers](https://pub.dev/packages/audioplayers) | MIT | Play the Morse sending tone |
| [camera](https://pub.dev/packages/camera) | BSD 3-Clause | Live camera frames for light decoding |
| [record](https://pub.dev/packages/record) | BSD 3-Clause | Live microphone stream for audio decoding |
| [torch_light](https://pub.dev/packages/torch_light) | Apache 2.0 | Toggle the LED for light sending |
| [share_plus](https://pub.dev/packages/share_plus) | BSD 3-Clause | Share decoded text via the system share sheet |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | MIT | Icon assets |

There are **no third-party advertising SDKs**, **no crash reporting
services**, and **no analytics platforms** integrated in SimplyMorse.

---

## 6. Children's Privacy

SimplyMorse is a general-audience utility app. It does not target children
and does not knowingly collect any data from anyone.

---

## 7. Changes to This Policy

If the app ever changes in a way that affects privacy (e.g., a new
permission or a third-party service is added), this policy will be updated
and the "Last updated" date will change. The policy is always available at:
[https://raw.githubusercontent.com/igrowing/SimplyMorse/refs/heads/main/PRIVACY_POLICY.md](https://raw.githubusercontent.com/igrowing/SimplyMorse/refs/heads/main/PRIVACY_POLICY.md)

---

## 8. Contact

Questions about this privacy policy:
[GitHub Issues](https://github.com/igrowing/SimplyMorse/issues) or open a
discussion at the repository above.
