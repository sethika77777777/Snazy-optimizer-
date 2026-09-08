# Snazy Optimizer

<p align="center">
  <img src="assets/banner.png" alt="Snazy Optimizer Banner" width="900">
</p>

<h1 align="center">Snazy Optimizer</h1>

<p align="center">
  <strong>Android Gaming Performance Optimizer</strong>
</p>

<p align="center">
  Version 1.0.10 • Android 10+ • Root & Non-Root
</p>

<p align="center">
  <a href="https://github.com/sethikaDV/Snazy-optimizer-/releases">
    <img src="https://img.shields.io/github/v/release/sethikaDV/Snazy-optimizer-?style=for-the-badge" alt="Latest Release">
  </a>
  <a href="https://github.com/sethikaDV/Snazy-optimizer-/releases">
    <img src="https://img.shields.io/github/downloads/sethikaDV/Snazy-optimizer-/total?style=for-the-badge" alt="Downloads">
  </a>
  <a href="https://github.com/sethikaDV/Snazy-optimizer-">
    <img src="https://img.shields.io/github/stars/sethikaDV/Snazy-optimizer-?style=for-the-badge" alt="Stars">
  </a>
  <img src="https://img.shields.io/badge/Android-10%2B-green?style=for-the-badge" alt="Android 10+">
</p>

---

# About Snazy Optimizer

Snazy Optimizer is an Android performance optimization application
designed for users who want a cleaner and more controlled gaming
environment.

The application provides different optimization paths depending on
whether the device has root access or is running in standard
non-root mode.

Snazy is designed to work with Android system capabilities instead
of pretending to provide system-level access that Android does not
allow to normal applications.

The goal is simple:

> Select your game, apply the available optimizations, and launch the
> game in an optimized environment.

---

# Version Information

| Property | Information |
|---|---|
| Application | Snazy Optimizer |
| Current Version | 1.0.10 |
| Platform | Android |
| Minimum Android | Android 10 |
| Minimum SDK | 29 |
| Target SDK | 34 |
| Framework | Flutter |
| Language | Dart / Kotlin |
| Application ID | `com.sethikadv.snazy` |
| Developer | SethikaDV |

---

# Screenshots

## Dashboard

<p align="center">
  <img src="assets/screenshots/dashboard.png" alt="Snazy Optimizer Dashboard" width="300">
</p>

The dashboard provides the main entry point to Snazy Optimizer and
allows the user to access the available optimization features.

---

## Game Selection

<p align="center">
  <img src="assets/screenshots/game-select.png" alt="Game Selection Screen" width="300">
</p>

The game selection screen allows the user to choose the game that
will be optimized.

---

## Optimization

<p align="center">
  <img src="assets/screenshots/optimizer.png" alt="Optimizer Screen" width="300">
</p>

The optimizer applies the available actions according to the current
device mode and available Android permissions.

---

## Safe Apps

<p align="center">
  <img src="assets/screenshots/safe-apps.png" alt="Safe Apps Screen" width="300">
</p>

Safe Apps provides a way to keep selected applications protected from
optimization-related actions.

---

## Device Information

<p align="center">
  <img src="assets/screenshots/device-info.png" alt="Device Information" width="300">
</p>

The application can display available device information that can
help the user understand the current device state.

---

# Features

| Feature | Root Mode | Non-Root Mode |
|---|:---:|:---:|
| Game Selection | Yes | Yes |
| Game Launching | Yes | Yes |
| Performance Optimization | Yes | Limited |
| System-Level Actions | Yes | Limited |
| App Management | Yes | Limited |
| Safe Apps | Yes | Yes |
| Device Information | Yes | Yes |
| Restore Support | Yes | Yes |
| Android System Settings | Yes | Yes |

The exact capabilities available to the application depend on the
Android version, device manufacturer, permissions and whether root
access is available.

---

# Root Mode

When root access is available, Snazy Optimizer can use additional
Android system capabilities that are not normally available to
standard applications.

Root mode is intended for users who already have a properly configured
root environment.

Snazy does not attempt to root a device from inside the application.

The application detects available root access and uses the appropriate
optimization path.

### Root Mode Capabilities

Depending on the device and Android version, root mode can provide
access to operations such as:

- System-level optimization actions
- Application management
- Background application control
- Application freezing and restoring
- Additional performance-related operations
- More advanced device control

The availability of individual operations depends on the Android
environment.

---

# Non-Root Mode

Snazy Optimizer also supports devices without root access.

Android intentionally restricts third-party applications from
performing many system-level operations.

Because of these restrictions, non-root mode does not pretend to have
root privileges.

Instead, Snazy uses operations that are available to normal Android
applications and provides the user with the appropriate Android
system actions where required.

### Non-Root Mode

| Operation | Availability |
|---|---|
| Game selection | Available |
| Game launching | Available |
| Device information | Available |
| Supported optimization actions | Available |
| Root-only system modifications | Not available |
| Direct system-level app control | Restricted by Android |

---

# What Android Allows vs What Snazy Does

One of the important design principles of Snazy Optimizer is not to
claim functionality that Android itself does not permit.

| Requested Operation | Android Limitation | Snazy Approach |
|---|---|---|
| Grant root from the app | Android apps cannot root devices by themselves | Detect existing root access |
| DirectX rendering | DirectX is not the normal Android graphics API | Use supported Android graphics technologies |
| Kill arbitrary background apps | Restricted on modern Android | Use supported system mechanisms |
| Per-app CPU/RAM statistics | Restricted on modern Android | Use available device-level information |
| Freeze applications | Requires elevated access | Available where the required access exists |
| Restore disabled applications | Requires appropriate permissions | Restore applications managed by Snazy |

This means Snazy focuses on real Android functionality rather than
fake optimization animations or simulated performance numbers.

---

# Game Optimization

Snazy Optimizer is designed around a simple gaming workflow.

```text
Open Snazy
     |
     v
Select Optimization Mode
     |
     v
Select Game
     |
     v
Apply Available Optimizations
     |
     v
Launch Game
