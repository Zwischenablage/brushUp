package com.brushup.snapgatekeeper

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.brushup.snapgatekeeper.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            BlockerForegroundService.start(this)
            refreshStatus()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.accessibilityButton.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        binding.usageAccessButton.setOnClickListener {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }

        binding.serviceToggleButton.setOnClickListener {
            if (GatekeeperConfig.isServiceEnabled(this)) {
                BlockerForegroundService.stop(this)
                refreshStatus()
            } else {
                startGatewayService()
            }
        }
    }

    private fun startGatewayService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        BlockerForegroundService.start(this)
        refreshStatus()
    }

    override fun onResume() {
        super.onResume()
        PackageBlocker.applySuspension(this)
        refreshStatus()
    }

    private fun refreshStatus() {
        val target = GatekeeperConfig.targetPackage(this)
        binding.targetPackageText.text = getString(R.string.label_target_package) + ": " + target

        val isDeviceOwner = PackageBlocker.isDeviceOwner(this)
        binding.deviceOwnerStatusText.text = statusLabel(isDeviceOwner)
        binding.deviceOwnerStatusText.setTextColor(statusColor(isDeviceOwner))
        binding.deviceOwnerHintText.text = if (isDeviceOwner) {
            ""
        } else {
            getString(R.string.device_owner_hint)
        }

        val a11yEnabled = isAccessibilityServiceEnabled()
        binding.accessibilityStatusText.text = statusLabel(a11yEnabled)
        binding.accessibilityStatusText.setTextColor(statusColor(a11yEnabled))

        val usageGranted = isUsageAccessGranted()
        binding.usageAccessStatusText.text = statusLabel(usageGranted)
        binding.usageAccessStatusText.setTextColor(statusColor(usageGranted))

        val serviceRunning = GatekeeperConfig.isServiceEnabled(this)
        binding.serviceStatusText.text = statusLabel(serviceRunning)
        binding.serviceStatusText.setTextColor(statusColor(serviceRunning))
        binding.serviceToggleButton.setText(
            if (serviceRunning) R.string.btn_stop_service else R.string.btn_start_service
        )
    }

    private fun statusLabel(active: Boolean) =
        getString(if (active) R.string.state_active else R.string.state_inactive)

    private fun statusColor(active: Boolean) =
        if (active) getColor(R.color.ok) else getColor(R.color.warn)

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expected = "$packageName/${GatekeeperAccessibilityService::class.java.name}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        for (component in splitter) {
            if (component.equals(expected, ignoreCase = true)) return true
        }
        return false
    }

    private fun isUsageAccessGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
