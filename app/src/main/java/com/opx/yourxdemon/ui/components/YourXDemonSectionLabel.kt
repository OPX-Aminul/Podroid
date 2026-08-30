package com.opx.yourxdemon.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.opx.yourxdemon.ui.theme.YourXDemonTokens

/**
 * Tiny uppercase tracked label used as a section heading throughout the app.
 * Pairs naturally with YourXDemonListRow groups.
 */
@Composable
fun YourXDemonSectionLabel(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontFamily = YourXDemonTokens.ui(),
        fontWeight = FontWeight.Medium,
        modifier = modifier
            .padding(top = YourXDemonTokens.Spacing.LG, bottom = YourXDemonTokens.Spacing.XS),
    )
}
