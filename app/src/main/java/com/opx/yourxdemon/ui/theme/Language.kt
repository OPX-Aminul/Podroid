/*
 * YourXDemon - Rootless Podman for Android
 * Copyright (C) 2024-2026 YourXDemon contributors
 */
package com.opx.yourxdemon.ui.theme

import androidx.compose.runtime.compositionLocalOf

/**
 * Provides the current language code (e.g., "zh", "en") to Compose components.
 * Note: Language is now managed by Android's resource system automatically,
 * so this LocalLanguage is primarily for programmatic language detection.
 */
val LocalLanguage = compositionLocalOf<String> { "en" }
