package com.opx.yourxdemon.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Build a Material3 Typography that uses Inter as the base UI font family.
 * Called from YourXDemonTheme — must be @Composable so we can resolve the
 * asset-backed Inter family via LocalContext (see YourXDemonTokens.ui()).
 */
@Composable @ReadOnlyComposable
fun buildYourXDemonTypography(): Typography {
    val ui = YourXDemonTokens.ui()
    return Typography(
        displayLarge = TextStyle(
            fontFamily    = ui,
            fontWeight    = FontWeight.Thin,
            fontSize      = YourXDemonTokens.TypeSize.Display,
            letterSpacing = (-0.02).sp,
            lineHeight    = 34.sp,
        ),
        headlineSmall = TextStyle(
            fontFamily = ui,
            fontWeight = FontWeight.SemiBold,
            fontSize   = YourXDemonTokens.TypeSize.Headline,
            lineHeight = 26.sp,
        ),
        titleMedium = TextStyle(
            fontFamily    = ui,
            fontWeight    = FontWeight.Normal,
            fontSize      = YourXDemonTokens.TypeSize.Title,
            letterSpacing = (-0.005).sp,
        ),
        bodyMedium = TextStyle(
            fontFamily = ui,
            fontWeight = FontWeight.Normal,
            fontSize   = YourXDemonTokens.TypeSize.Body,
            lineHeight = 18.sp,
        ),
        labelMedium = TextStyle(
            fontFamily    = ui,
            fontWeight    = FontWeight.Normal,
            fontSize      = YourXDemonTokens.TypeSize.Label,
            letterSpacing = 1.4.sp,
        ),
    )
}