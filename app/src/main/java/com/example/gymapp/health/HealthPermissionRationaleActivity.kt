package com.example.gymapp.health

import android.app.Activity
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import com.example.gymapp.R

/**
 * Shown by Health Connect when the user asks why GymApp reads workout data (the
 * ACTION_SHOW_PERMISSIONS_RATIONALE intent, and the Android 14 VIEW_PERMISSION_USAGE alias).
 * It displays text only, takes no input and reads nothing from the incoming intent.
 *
 * Strings: health_import_rationale_title and health_import_rationale_body (EN / UK / RU).
 */
class HealthPermissionRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val density = resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        root.addView(
            TextView(this).apply {
                text = getString(R.string.health_import_rationale_title)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }
        )
        root.addView(
            TextView(this).apply {
                text = getString(R.string.health_import_rationale_body)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding(0, padding / 2, 0, 0)
            }
        )
        setContentView(root)
    }
}
