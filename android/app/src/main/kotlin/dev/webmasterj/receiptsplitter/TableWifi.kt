package dev.webmasterj.receiptsplitter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi for the live bill, without the internet or the system hotspot settings:
 *  - host: LocalOnlyHotspot = an app-owned hotspot (random name + password, no internet sharing),
 *  - guest: WifiNetworkSpecifier = connect only this app to the host's hotspot; the phone's normal
 *    Wi-Fi / mobile data keep working for everything else.
 */
class TableWifi(private val activity: Activity, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val cm = activity.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())

    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null
    private var pendingPermission: MethodChannel.Result? = null

    companion object {
        const val PERMISSION_REQUEST = 4711
    }

    private fun wifiPermission(): String =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensurePermission" -> ensurePermission(result)
            "startHotspot" -> startHotspot(result)
            "stopHotspot" -> { stopHotspot(); result.success(null) }
            "join" -> join(call, result)
            "leave" -> { leave(); result.success(null) }
            "bindToHost" -> result.success(bindToHost(call.argument<String>("host")!!))
            else -> result.notImplemented()
        }
    }

    private fun ensurePermission(result: MethodChannel.Result) {
        val p = wifiPermission()
        if (activity.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(p), PERMISSION_REQUEST)
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(granted: Boolean) {
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    @Suppress("DEPRECATION")
    private fun startHotspot(result: MethodChannel.Result) {
        reservation?.let { result.success(describe(it)); return }
        var replied = false
        fun reply(block: () -> Unit) { if (!replied) { replied = true; block() } }
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    reply { result.success(describe(r)) }
                }

                override fun onStopped() {
                    // Android turned it off (e.g. the normal hotspot was switched on): the QR code is stale
                    reservation = null
                    channel.invokeMethod("hotspotStopped", null)
                }

                override fun onFailed(reason: Int) {
                    val why = when (reason) {
                        ERROR_INCOMPATIBLE_MODE -> "incompatible" // the normal hotspot is on
                        ERROR_TETHERING_DISALLOWED -> "disallowed"
                        ERROR_NO_CHANNEL -> "no_channel"
                        else -> "failed_$reason"
                    }
                    reply { result.error(why, "Could not start the table Wi-Fi ($why)", null) }
                }
            }, main)
        } catch (e: SecurityException) {
            reply { result.error("permission", e.message, null) }
        } catch (e: IllegalStateException) {
            reply { result.error("busy", e.message, null) } // a request is already running
        }
    }

    @Suppress("DEPRECATION")
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= 30) {
            val c = r.softApConfiguration
            val ssid = if (Build.VERSION.SDK_INT >= 33) c.wifiSsid?.toString()?.trim('"') else c.ssid
            // 1 = WPA2, 2 = WPA3 transition (WPA2 also works), 3 = WPA3 only
            return mapOf("ssid" to ssid, "password" to c.passphrase, "security" to c.securityType)
        }
        val c = r.wifiConfiguration
        return mapOf("ssid" to c?.SSID?.trim('"'), "password" to c?.preSharedKey?.trim('"'), "security" to 1)
    }

    private fun stopHotspot() {
        reservation?.close()
        reservation = null
    }

    private fun join(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) {
            result.error("old_android", "Needs Android 10 or newer", null)
            return
        }
        val ssid = call.argument<String>("ssid")!!
        val password = call.argument<String>("password")!!
        val security = call.argument<Int>("security") ?: 1
        leave()
        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (security == 3) setWpa3Passphrase(password) else setWpa2Passphrase(password)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()
        var replied = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // every socket of this app (incl. Dart's) now goes through the table Wi-Fi
                cm.bindProcessToNetwork(network)
                main.post { if (!replied) { replied = true; result.success(true) } }
            }

            override fun onUnavailable() {
                main.post { if (!replied) { replied = true; result.error("unavailable", "Could not connect to $ssid", null) } }
            }

            override fun onLost(network: Network) {
                cm.bindProcessToNetwork(null)
            }
        }
        joinCallback = cb
        try {
            cm.requestNetwork(request, cb, 60_000) // the system shows "Connect to <ssid>?"
        } catch (e: SecurityException) {
            joinCallback = null
            result.error("permission", e.message, null)
        }
    }

    /**
     * The guest joined the table Wi-Fi from the camera (system-wide). That network has no internet, so
     * Android may keep mobile data as the default and the host would be unreachable: send this app's
     * traffic through the Wi-Fi network whose subnet contains the host.
     */
    private fun bindToHost(host: String): Boolean {
        val target = runCatching { java.net.InetAddress.getByName(host) }.getOrNull() ?: return false
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            val lp = cm.getLinkProperties(n) ?: continue
            if (lp.linkAddresses.any { la -> sameSubnet(la.address, target, la.prefixLength) }) {
                return cm.bindProcessToNetwork(n)
            }
        }
        return false
    }

    private fun sameSubnet(a: java.net.InetAddress, b: java.net.InetAddress, prefix: Int): Boolean {
        val x = a.address
        val y = b.address
        if (x.size != y.size) return false
        for (i in x.indices) {
            val bits = (prefix - i * 8).coerceIn(0, 8)
            val mask = (0xFF shl (8 - bits)) and 0xFF
            if ((x[i].toInt() and mask) != (y[i].toInt() and mask)) return false
        }
        return true
    }

    private fun leave() {
        cm.bindProcessToNetwork(null)
        joinCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        joinCallback = null
    }

    fun dispose() {
        stopHotspot()
        leave()
    }
}
