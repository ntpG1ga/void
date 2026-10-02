package com.metascript.voidsample

import android.content.Context
import android.view.MotionEvent
import android.view.Surface
import java.io.File

object VoidNative {
    init {
        System.loadLibrary("VoidAndroid")
        System.loadLibrary("VoidJni")
    }

    // Phases of src/sokol/pointer.h.
    private const val DOWN = 0
    private const val MOVE = 1
    private const val UP = 2
    private const val CANCEL = 3

    external fun attach(surface: Surface, width: Int, height: Int)
    external fun resize(width: Int, height: Int)
    external fun frame()
    external fun detach()
    external fun touch(phase: Int, id: Int, x: Float, y: Float)
    private external fun setAssetRoot(path: String)

    private var prepared = false

    // Void loads "assets/font.ttf" with fopen, which cannot see inside the APK: copy the APK's
    // assets to filesDir/assets and point Void there. Call before the first surface is shown.
    @Synchronized
    fun prepare(context: Context) {
        if (prepared) return
        copyAssets(context, "", File(context.filesDir, "assets"))
        setAssetRoot(context.filesDir.absolutePath)
        prepared = true
    }

    // Hands a MotionEvent to Void as raw pointer events, in surface pixels. Void hit-tests
    // them itself: the whole UI is one GL surface, so Android cannot tell what was touched.
    fun forward(e: MotionEvent) {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> push(e, e.actionIndex, DOWN)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> push(e, e.actionIndex, UP)
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) push(e, i, MOVE)
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount) push(e, i, CANCEL)
        }
    }

    // AssetManager cannot tell a file from a folder: a name that lists children is a folder,
    // and one that fails to open (the system's own images/, webkit/) is skipped.
    private fun copyAssets(context: Context, path: String, into: File) {
        into.mkdirs()
        for (name in context.assets.list(path) ?: emptyArray()) {
            val child = if (path.isEmpty()) name else "$path/$name"
            if (!context.assets.list(child).isNullOrEmpty()) {
                copyAssets(context, child, File(into, name))
                continue
            }
            try {
                context.assets.open(child).use { src -> File(into, name).outputStream().use { src.copyTo(it) } }
            } catch (_: java.io.IOException) {
            }
        }
    }

    private fun push(e: MotionEvent, index: Int, phase: Int) {
        touch(phase, e.getPointerId(index), e.getX(index), e.getY(index))
    }
}
