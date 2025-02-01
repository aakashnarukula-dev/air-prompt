# Air Prompt Android Companion

Tiny Android wrapper app for Air Prompt.

What it does:

- keeps the existing mobile web UI unchanged by loading it in a `WebView`
- registers this phone with the local Air Prompt backend
- polls for pending launch requests from the Mac app
- opens straight into the same session URL when the Mac app starts

Current limitation:

- Android may not foreground a fully terminated app without user interaction every time
- once the companion app has been opened and paired, it can resume directly into new sessions while Android keeps the process available

Build:

```bash
cd /Users/aakashnarukula/Developer/Air\ Prompt/android-companion
gradle assembleDebug
```

If `gradle` is not installed on this Mac, open the folder in Android Studio and let it generate/import the Gradle wrapper.
