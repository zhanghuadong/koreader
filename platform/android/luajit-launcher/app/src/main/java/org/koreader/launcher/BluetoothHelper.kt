package org.koreader.launcher

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log

/* Bluetooth scanning, pairing and profile connection for the reader's Bluetooth dialog.
 * Connecting profiles goes through hidden APIs, which works because the app runs as the system uid. */
@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
class BluetoothHelper(private val context: Context) {
    private val tag = this::class.java.simpleName
    private val adapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val found = LinkedHashMap<String, BluetoothDevice>()
    private val pendingConnect = HashSet<String>()
    private var pendingScan = false
    private var registered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    device?.let { synchronized(found) { found[it.address] = it } }
                }
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    if (state == BluetoothAdapter.STATE_ON && pendingScan) {
                        pendingScan = false
                        adapter?.startDiscovery()
                    }
                }
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                    if (device != null && state == BluetoothDevice.BOND_BONDED && pendingConnect.remove(device.address)) {
                        connectProfiles(device)
                    }
                }
            }
        }
    }

    private fun register() {
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        context.registerReceiver(receiver, filter)
        registered = true
    }

    fun release() {
        pendingScan = false
        adapter?.cancelDiscovery()
        if (registered) {
            try {
                context.unregisterReceiver(receiver)
            } catch (e: Exception) {
                Log.w(tag, "unregister failed: $e")
            }
            registered = false
        }
    }

    fun startScan(): Boolean {
        val adapter = adapter ?: return false
        register()
        synchronized(found) { found.clear() }
        return try {
            if (adapter.isEnabled) {
                if (adapter.isDiscovering) adapter.cancelDiscovery()
                adapter.startDiscovery()
            } else {
                pendingScan = true
                adapter.enable()
            }
        } catch (e: Exception) {
            Log.e(tag, "scan failed: $e")
            pendingScan = false
            false
        }
    }

    fun stopScan() {
        pendingScan = false
        adapter?.cancelDiscovery()
    }

    fun isScanning(): Boolean = pendingScan || (adapter?.isDiscovering ?: false)

    private fun isConnected(device: BluetoothDevice): Boolean = try {
        device.javaClass.getMethod("isConnected").invoke(device) as Boolean
    } catch (e: Exception) {
        false
    }

    private fun clean(s: String?): String? = s?.replace('\t', ' ')?.replace('\n', ' ')?.trim()?.ifEmpty { null }

    /* One device per line: address \t name \t bonded(0/1) \t connected(0/1).
     * Paired devices come first; discovered devices without a name are skipped. */
    fun getDevices(): String {
        val adapter = adapter ?: return ""
        val devices = LinkedHashMap<String, BluetoothDevice>()
        try {
            if (adapter.isEnabled) adapter.bondedDevices?.forEach { devices[it.address] = it }
        } catch (e: Exception) {
            Log.w(tag, "bonded devices unavailable: $e")
        }
        synchronized(found) { found.values.forEach { devices.putIfAbsent(it.address, it) } }
        return devices.values.mapNotNull { d ->
            val bonded = d.bondState == BluetoothDevice.BOND_BONDED
            val name = clean(d.name) ?: if (bonded) d.address else return@mapNotNull null
            listOf(d.address, name, if (bonded) "1" else "0", if (isConnected(d)) "1" else "0").joinToString("\t")
        }.joinToString("\n")
    }

    fun connect(address: String): Boolean {
        val adapter = adapter ?: return false
        return try {
            val device = adapter.getRemoteDevice(address)
            adapter.cancelDiscovery()
            if (device.bondState == BluetoothDevice.BOND_BONDED) {
                connectProfiles(device)
                true
            } else {
                register()
                pendingConnect.add(address)
                device.createBond()
            }
        } catch (e: Exception) {
            Log.e(tag, "connect failed: $e")
            false
        }
    }

    private fun connectProfiles(device: BluetoothDevice) {
        val adapter = adapter ?: return
        val profiles = when (device.bluetoothClass?.majorDeviceClass) {
            BluetoothClass.Device.Major.AUDIO_VIDEO -> listOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET)
            else -> listOf(PROFILE_HID_HOST)
        }
        for (profile in profiles) {
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(p: Int, proxy: BluetoothProfile) {
                    try {
                        proxy.javaClass.getMethod("connect", BluetoothDevice::class.java).invoke(proxy, device)
                    } catch (e: Exception) {
                        Log.e(tag, "profile $p connect failed: $e")
                    }
                    adapter.closeProfileProxy(p, proxy)
                }

                override fun onServiceDisconnected(p: Int) {}
            }, profile)
        }
    }

    companion object {
        // BluetoothProfile.HID_HOST is hidden
        private const val PROFILE_HID_HOST = 4
    }
}
