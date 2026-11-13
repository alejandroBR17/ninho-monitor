package com.jortanviewer.jortan_viewer

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.text.TextUtils
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.view.View
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.*
import android.widget.*

class RemoteViewerActivity : Activity() {
    private lateinit var web: WebView
    private lateinit var root: FrameLayout
    private lateinit var content: LinearLayout
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var origin: Uri
    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
    private fun sameOrigin(uri: Uri): Boolean = uri.scheme == "https" && uri.host == origin.host && uri.port == origin.port && uri.userInfo == null
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        origin = Uri.parse(intent.getStringExtra("url") ?: "")
        if (origin.scheme != "https" || origin.host.isNullOrBlank() || origin.userInfo != null) { finish(); return }
        root = FrameLayout(this)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.rgb(16,27,28)) }
        val toolbar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16),dp(8),dp(16),dp(8)); setBackgroundColor(Color.rgb(23,37,38)) }
        toolbar.addView(Button(this).apply { text = "‹ Voltar"; minimumHeight = dp(48); setTextColor(Color.rgb(119,226,194)); setBackgroundColor(Color.TRANSPARENT); isAllCaps = false; typeface = Typeface.create("sans-serif", Typeface.NORMAL); setOnClickListener { finish() } })
        toolbar.addView(TextView(this).apply { text = "Acesso remoto"; textSize = 16f; setTextColor(Color.rgb(242,247,245)); setPadding(dp(16),dp(8),dp(8),dp(8)); maxLines = 1; ellipsize = TextUtils.TruncateAt.END }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        content.addView(toolbar)
        web = WebView(this)
        web.setBackgroundColor(Color.rgb(16,27,28))
        web.settings.apply { javaScriptEnabled = true; domStorageEnabled = true; allowFileAccess = false; allowContentAccess = false; mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW; mediaPlaybackRequiresUserGesture = true; setSupportMultipleWindows(false) }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = !sameOrigin(request.url)
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) { handler.cancel(); Toast.makeText(this@RemoteViewerActivity, "Não foi possível validar o endereço HTTPS da ponte.", Toast.LENGTH_LONG).show() }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (fullscreen != null) { callback.onCustomViewHidden(); return }
                fullscreen = view; fullscreenCallback = callback; content.visibility = View.GONE
                root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            }
            override fun onHideCustomView() { closeFullscreen() }
        }
        content.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(content, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
        if (state == null) web.loadUrl(origin.toString()) else web.restoreState(state)
    }
    private fun closeFullscreen() { fullscreen?.let { root.removeView(it) }; fullscreen = null; content.visibility = View.VISIBLE; fullscreenCallback?.onCustomViewHidden(); fullscreenCallback = null }
    @Deprecated("Legacy back compatibility")
    override fun onBackPressed() { if (fullscreen != null) closeFullscreen() else if (web.canGoBack()) web.goBack() else super.onBackPressed() }
    override fun onPause() { if (::web.isInitialized) { web.evaluateJavascript("window.dispatchEvent(new Event('blur'))", null); web.onPause() }; super.onPause() }
    override fun onResume() { super.onResume(); if (::web.isInitialized) web.onResume() }
    override fun onSaveInstanceState(out: Bundle) { if (::web.isInitialized) web.saveState(out); super.onSaveInstanceState(out) }
    override fun onDestroy() { if (::web.isInitialized) { web.stopLoading(); web.destroy() }; super.onDestroy() }
}
