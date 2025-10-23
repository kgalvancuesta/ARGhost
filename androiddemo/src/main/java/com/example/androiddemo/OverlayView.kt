package com.example.androiddemo

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

class OverlayView(context: Context, attrs: AttributeSet?) : View(context, attrs) {
    private val paint = Paint().apply {
        color = 0xFF00FF00.toInt() // green
        style = Paint.Style.STROKE
        strokeWidth = 6f
    }

    var box: RectF? = null
        set(value) {
            field = value
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        box?.let { canvas.drawRect(it, paint) }
    }
}
