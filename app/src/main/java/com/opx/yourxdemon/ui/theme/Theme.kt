/*
 * YourXDemon Compose theme.
 *
 * Default identity: fixed dark/light palette derived from YourXDemonTokens, with
 * a lime-green accent (#4ade80). Material You wallpaper-derived dynamic color
 * is OFF by default — users opt in via Settings → Appearance → Dynamic color,
 * which flows in via the dynamicColor parameter.
 */
package com.opx.yourxdemon.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val YourXDemonDark = darkColorScheme(
    primary             = YourXDemonAccent,
    onPrimary           = YourXDemonAccentInk,
    primaryContainer    = YourXDemonDarkSurface2,
    onPrimaryContainer  = YourXDemonDarkText,

    secondary           = YourXDemonAccent,
    onSecondary         = YourXDemonAccentInk,
    secondaryContainer  = YourXDemonDarkSurface2,
    onSecondaryContainer= YourXDemonDarkText,

    tertiary            = YourXDemonAmber,
    onTertiary          = YourXDemonAccentInk,

    background          = YourXDemonDarkBg,
    onBackground        = YourXDemonDarkText,
    surface             = YourXDemonDarkSurface,
    onSurface           = YourXDemonDarkText,
    surfaceVariant      = YourXDemonDarkSurface2,
    onSurfaceVariant    = YourXDemonDarkTextMute,
    surfaceContainerHighest = YourXDemonDarkSurface2,

    outline             = YourXDemonDarkBorder,
    outlineVariant      = YourXDemonDarkBorder,

    error               = YourXDemonRed,
    onError             = YourXDemonDarkText,
    errorContainer      = YourXDemonDarkSurface2,
    onErrorContainer    = YourXDemonRed,
)

private val YourXDemonLight = lightColorScheme(
    primary             = YourXDemonAccent,
    onPrimary           = YourXDemonAccentInk,
    primaryContainer    = YourXDemonLightSurface2,
    onPrimaryContainer  = YourXDemonLightText,

    secondary           = YourXDemonAccent,
    onSecondary         = YourXDemonAccentInk,
    secondaryContainer  = YourXDemonLightSurface2,
    onSecondaryContainer= YourXDemonLightText,

    tertiary            = YourXDemonAmber,
    onTertiary          = YourXDemonLightText,

    background          = YourXDemonLightBg,
    onBackground        = YourXDemonLightText,
    surface             = YourXDemonLightSurface,
    onSurface           = YourXDemonLightText,
    surfaceVariant      = YourXDemonLightSurface2,
    onSurfaceVariant    = YourXDemonLightTextMute,
    surfaceContainerHighest = YourXDemonLightSurface2,

    outline             = YourXDemonLightBorder,
    outlineVariant      = YourXDemonLightBorder,

    error               = YourXDemonRed,
    onError             = YourXDemonLightText,
    errorContainer      = YourXDemonLightSurface2,
    onErrorContainer    = YourXDemonRed,
)

@Composable
fun YourXDemonTheme(
    darkTheme: Boolean? = null,
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val effectiveDark = darkTheme ?: isSystemInDarkTheme()
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (effectiveDark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        effectiveDark -> YourXDemonDark
        else          -> YourXDemonLight
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography  = buildYourXDemonTypography(),
        content     = content,
    )
}
