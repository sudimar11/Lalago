# Rider notification sounds

- **reassign.wav** – Used only for order reassignment (timeout) notifications. Do not use for other notification types (new_order, food_ready, etc.). When a rider's order expires and is reassigned, this sound is played so the rider can tell the event apart from others.
  - In-app playback uses this file from `assets/audio/`.
  - For Android background notifications, a copy is in `android/app/src/main/res/raw/reassign.wav`.
  - For iOS background notifications with custom sound, `reassign.wav` is included in the Xcode project (Runner) as a Copy Bundle Resource so it is in the app bundle.
