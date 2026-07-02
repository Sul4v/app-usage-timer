package com.sodhera.capsule.tracking

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * The floating timer: a small, draggable capsule drawn over whatever app is
 * open (TYPE_APPLICATION_OVERLAY, so it needs the "display over other apps"
 * permission). A dot + the minutes used today, tinted green→yellow→red.
 */
class OverlayCapsule(private val context: Context) {
    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val prefs = context.getSharedPreferences("capsule_overlay", Context.MODE_PRIVATE)

    private var root: LinearLayout? = null
    private var dot: View? = null
    private var label: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    private fun dp(v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    @SuppressLint("ClickableViewAccessibility")
    private fun build() {
        if (root != null) return

        val capsule = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), dp(7f), dp(12f), dp(7f))
            background = GradientDrawable().apply {
                cornerRadius = dp(999f).toFloat()
                setColor(Color.parseColor("#D9121212"))
            }
            elevation = dp(4f).toFloat()
        }

        val dotView = View(context).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL }
            layoutParams = LinearLayout.LayoutParams(dp(8f), dp(8f)).apply {
                marginEnd = dp(7f)
            }
        }
        val text = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        }
        capsule.addView(dotView)
        capsule.addView(text)

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt("x", dp(16f))
            y = prefs.getInt("y", dp(64f))
        }

        // Drag to reposition; position is remembered.
        capsule.setOnTouchListener(object : View.OnTouchListener {
            private var startX = 0; private var startY = 0
            private var touchX = 0f; private var touchY = 0f
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = lp.x; startY = lp.y
                        touchX = e.rawX; touchY = e.rawY
                    }
                    MotionEvent.ACTION_MOVE -> {
                        lp.x = startX + (e.rawX - touchX).toInt()
                        lp.y = startY + (e.rawY - touchY).toInt()
                        runCatching { wm.updateViewLayout(capsule, lp) }
                    }
                    MotionEvent.ACTION_UP -> {
                        if (abs(e.rawX - touchX) > 8 || abs(e.rawY - touchY) > 8) {
                            prefs.edit().putInt("x", lp.x).putInt("y", lp.y).apply()
                        }
                    }
                }
                return true
            }
        })

        root = capsule
        dot = dotView
        label = text
        params = lp
    }

    /** Show (attaching if needed) and refresh color + text. */
    fun update(text: String, color: Int) {
        build()
        val capsule = root ?: return
        label?.text = text
        (dot?.background as? GradientDrawable)?.setColor(color)
        if (capsule.parent == null) {
            runCatching { wm.addView(capsule, params) }
                .onFailure { android.util.Log.w("Capsule", "overlay attach failed", it) }
        }
    }

    fun hide() {
        val capsule = root ?: return
        if (capsule.parent != null) {
            runCatching { wm.removeView(capsule) }
        }
    }
}
