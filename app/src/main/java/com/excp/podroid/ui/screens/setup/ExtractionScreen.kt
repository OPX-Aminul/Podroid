package com.excp.podroid.ui.screens.setup

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.excp.podroid.R
import com.excp.podroid.ui.components.AdaptiveContainer
import com.excp.podroid.ui.theme.PodroidTokens

/**
 * Full-screen extraction page shown after the setup wizard completes.
 *
 * Displays an indeterminate progress bar and status text while
 * PodroidApplication.extractAssets() copies kernel, QEMU, and rootfs
 * assets from the APK to internal storage.
 *
 * Once extraction finishes, [onExtractionComplete] fires and the
 * NavGraph navigates to the Home screen.
 */
@Composable
fun ExtractionScreen(
    windowSizeClass: WindowSizeClass,
    extractionComplete: Boolean,
    onExtractionComplete: () -> Unit,
) {
    // Indeterminate progress animation
    val infiniteTransition = rememberInfiniteTransition(label = "extraction")
    val progress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "progress",
    )

    LaunchedEffect(extractionComplete) {
        if (extractionComplete) {
            onExtractionComplete()
        }
    }

    AdaptiveContainer(
        windowSizeClass = windowSizeClass,
        modifier = Modifier.fillMaxSize(),
        maxWidth = 600,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = PodroidTokens.Spacing.XL),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(PodroidTokens.Spacing.XL * 2))

            Text(
                text = stringResource(R.string.extracting_title),
                style = MaterialTheme.typography.displayLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )

            Spacer(Modifier.height(PodroidTokens.Spacing.SM))

            Text(
                text = stringResource(R.string.extracting_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(PodroidTokens.Spacing.XL))

            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(PodroidTokens.Spacing.SM))

            Text(
                text = stringResource(R.string.extracting_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
