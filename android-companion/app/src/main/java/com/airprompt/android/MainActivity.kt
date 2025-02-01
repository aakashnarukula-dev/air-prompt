package com.airprompt.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import com.airprompt.android.databinding.ActivityMainBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var pollJob: Job? = null

    private val prefs by lazy {
        getSharedPreferences("airprompt_android", Context.MODE_PRIVATE)
    }

    private val deviceId by lazy {
        prefs.getString(KEY_DEVICE_ID, null) ?: Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            .orEmpty()
            .ifBlank { "android-${System.currentTimeMillis()}" }
            .also { prefs.edit().putString(KEY_DEVICE_ID, it).apply() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setupWebView()
        if (!loadIntentUrl(intent?.dataString)) {
            loadRememberedUrl()
        }
    }

    override fun onNewIntent(intent: android.content.Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!loadIntentUrl(intent?.dataString)) {
            loadRememberedUrl()
        }
    }

    override fun onResume() {
        super.onResume()
        startPolling()
    }

    override fun onPause() {
        pollJob?.cancel()
        pollJob = null
        super.onPause()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        binding.webView.settings.javaScriptEnabled = true
        binding.webView.settings.domStorageEnabled = true
        binding.webView.settings.mediaPlaybackRequiresUserGesture = false
        binding.webView.settings.allowContentAccess = true
        binding.webView.settings.allowFileAccess = false
        binding.webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                request.grant(request.resources)
            }
        }
        binding.webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                if (!url.isNullOrBlank()) {
                    rememberUrl(url)
                    val backendBaseUrl = URL(url).origin()
                    rememberBackendBaseUrl(backendBaseUrl)
                    scope.launch(Dispatchers.IO) {
                        registerDevice(backendBaseUrl)
                    }
                    startLaunchMonitor()
                }
                showWebView()
            }
        }
    }

    private fun loadRememberedUrl() {
        val lastUrl = prefs.getString(KEY_LAST_URL, null)
        if (lastUrl.isNullOrBlank()) {
            showWaitingState()
            return
        }
        binding.webView.loadUrl(lastUrl)
    }

    private fun loadIntentUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        rememberUrl(url)
        rememberBackendBaseUrl(URL(url).origin())
        binding.webView.loadUrl(url)
        return true
    }

    private fun startPolling() {
        val backendBaseUrl = prefs.getString(KEY_BACKEND_BASE_URL, null)
        if (backendBaseUrl.isNullOrBlank()) {
            showWaitingState()
            return
        }
        pollJob?.cancel()
        pollJob = scope.launch(Dispatchers.IO) {
            registerDevice(backendBaseUrl)
            while (isActive) {
                val launchUrl = fetchPendingLaunchUrl(backendBaseUrl)
                if (!launchUrl.isNullOrBlank() && launchUrl != prefs.getString(KEY_LAST_LAUNCH_URL, null)) {
                    prefs.edit().putString(KEY_LAST_LAUNCH_URL, launchUrl).apply()
                    launch(Dispatchers.Main) {
                        binding.webView.loadUrl(launchUrl)
                    }
                }
                delay(2_000)
            }
        }
    }

    private fun showWaitingState() {
        binding.statusText.visibility = View.VISIBLE
        binding.webView.visibility = View.INVISIBLE
    }

    private fun showWebView() {
        binding.statusText.visibility = View.GONE
        binding.webView.visibility = View.VISIBLE
    }

    private fun rememberUrl(url: String) {
        prefs.edit().putString(KEY_LAST_URL, url).apply()
    }

    private fun rememberBackendBaseUrl(url: String) {
        prefs.edit().putString(KEY_BACKEND_BASE_URL, url).apply()
    }

    private fun registerDevice(backendBaseUrl: String) {
        val payload = JSONObject()
            .put("deviceId", deviceId)
            .put("deviceName", android.os.Build.MODEL ?: "Android")
            .put("backendBaseUrl", backendBaseUrl)
        postJson("$backendBaseUrl/android/device", payload)
    }

    private fun startLaunchMonitor() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, LaunchMonitorService::class.java)
        )
    }

    private fun fetchPendingLaunchUrl(backendBaseUrl: String): String? {
        return fetchPendingLaunchUrlStatic(backendBaseUrl, deviceId)
    }

    private fun postJson(urlString: String, payload: JSONObject) {
        val connection = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 4_000
            readTimeout = 4_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
        }
        try {
            connection.outputStream.use { it.write(payload.toString().toByteArray()) }
            connection.inputStream.close()
        } catch (_: Exception) {
        } finally {
            connection.disconnect()
        }
    }

    private fun URL.origin(): String = "${protocol}//$host${if (port != -1) ":$port" else ""}"

    companion object {
        const val PREFS_NAME = "airprompt_android"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_LAST_URL = "last_url"
        const val KEY_BACKEND_BASE_URL = "backend_base_url"
        const val KEY_LAST_LAUNCH_URL = "last_launch_url"

        fun fetchPendingLaunchUrlStatic(backendBaseUrl: String, deviceId: String): String? {
            val url = URL("$backendBaseUrl/android/launch?deviceId=$deviceId")
            val connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 4_000
                readTimeout = 4_000
            }
            return try {
                val body = connection.inputStream.use { input ->
                    BufferedReader(InputStreamReader(input)).readText()
                }
                if (connection.responseCode !in 200..299) return null
                val payload = JSONObject(body)
                payload.optJSONObject("launch")?.optString("joinUrl")
            } catch (_: Exception) {
                null
            } finally {
                connection.disconnect()
            }
        }
    }
}
