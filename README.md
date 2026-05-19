# LastStats 🎵

<p align="center">
  <img src="https://img.shields.io/github/v/release/SanoBld/LastStats-App?style=flat-square&color=7C3AED&label=Version" alt="Latest Release">
  <img src="https://img.shields.io/github/actions/workflow/status/SanoBld/LastStats-App/build-all.yml?branch=main&style=flat-square&label=Builds" alt="Build Status">
  <img src="https://img.shields.io/github/license/SanoBld/LastStats-App?style=flat-square&color=555555" alt="License">
</p>

A modern, multiplatform application built with **Flutter** and **Material You (M3)** to visualize, track, and analyze your listening statistics in real-time using the **Last.fm** API.

---

## ✨ Features

* **Minimalist & Modern Design:** Clean interface inspired by technical aesthetics, optimized for quick and efficient data reading.

* **Material You & Advanced Theming:** Fully supports system dark/light modes, custom accent colors (via presets or raw Hex codes), and dynamic palette extraction (`palette_generator`) that shifts the app's accent colors based on your **Now Playing** album artwork.

* **Smart Image Resolution Chain:** Built-in multi-source artwork locator with an in-memory cache. If Last.fm doesn't provide a valid image, the app automatically falls back through the **iTunes Search API**, **Deezer API**, and **MusicBrainz / Cover Art Archive**.

* **Real Data & Flexible Timeframes:** Direct, seamless connection with the Last.fm API to fetch live user profiles, recent scrobbles, and ranked lists across customizable periods (7 days, 1 month, 3 months, 6 months, 12 months, or overall).

* **Zero Simulated Data:** The application purely processes functional, live API streams with robust network error handling and retry mechanisms.

* **Integrated Update Checker:** Automated version tracking using the GitHub Releases API to notify users instantly when a newer release or APK is available.

* **Multiplatform:** Architecture optimized to target Android, Windows, macOS, Linux, and Web from a single codebase.

---

## 🚀 Downloads & Automated Builds (CI/CD)

This project uses an automated multi-platform pipeline powered by **GitHub Actions**. Every update pushed to the repository simultaneously triggers release compilations for all target environments.

You can download the latest builds directly from the **Actions** tab of this repository:

* 🤖 **Android:** `laststats-android-apk` (Features native adaptive icons)
* 🪟 **Windows:** `laststats-windows-app`
* 🌐 **Web:** `laststats-web-app`
* 🍏 **macOS:** `laststats-macos-app`
* 🐧 **Linux:** `laststats-linux-app`

> ⚠️ **Warning / Stability Note:**
> Executables downloaded directly from the **Actions** tab include the very latest features and real-time code updates. Consequently, **these development builds are highly likely to contain bugs**. Some specific features might temporarily glitch, malfunction, or exhibit unstable behavior.

---

## 📦 Technologies Used

* **Framework:** Flutter (Dart)
* **Design System:** Material Design 3 (Material You)
* **Key Packages:**
  * `dynamic_color` – Dynamic system palette adaptation.
  * `palette_generator` – Contextual color profile extraction from album art.
  * `shared_preferences` – Persistent storage for user credentials and custom UI configurations.
  * `http` – Concurrent network management for REST requests.
  * `url_launcher` – External web redirection management.
* **API Integration:** Last.fm REST API, iTunes Search API, Deezer API, and Cover Art Archive.

---

## 📝 License

This project is open-source. Feel free to use, modify, or contribute to it.
