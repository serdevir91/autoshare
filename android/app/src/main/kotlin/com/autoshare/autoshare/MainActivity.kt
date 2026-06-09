package com.autoshare.app

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.android.play.agesignals.AgeSignalsException
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.model.AgeSignalsErrorCode
import com.google.android.play.agesignals.model.AgeSignalsVerificationStatus
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val fileOpsChannelName = "com.autoshare.app/file_ops"
    private val ageSignalsChannelName = "com.autoshare.app/age_signals"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileOpsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is missing.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val status = installApk(path)
                            if (status == null) {
                                result.error("APK_NOT_FOUND", "APK file was not found.", null)
                            } else {
                                result.success(status)
                            }
                        } catch (e: ActivityNotFoundException) {
                            result.error("INSTALLER_NOT_FOUND", "No package installer found.", e.message)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", "Could not open installer.", e.message)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ageSignalsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAgeSignals" -> checkAgeSignals(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkAgeSignals(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(
                mapOf(
                    "success" to false,
                    "supported" to false,
                    "shouldBlockAccess" to false,
                    "message" to "Play Age Signals requires Android 6.0 (API 23) or newer.",
                    "checkedAtMillis" to System.currentTimeMillis()
                )
            )
            return
        }

        try {
            val ageSignalsManager = AgeSignalsManagerFactory.create(applicationContext)
            ageSignalsManager
                .checkAgeSignals(AgeSignalsRequest.builder().build())
                .addOnSuccessListener { ageSignalsResult ->
                    val userStatus = ageSignalsResult.userStatus()
                    result.success(
                        mapOf(
                            "success" to true,
                            "supported" to true,
                            "shouldBlockAccess" to
                                (userStatus == AgeSignalsVerificationStatus.SUPERVISED_APPROVAL_DENIED),
                            "userStatus" to ageSignalsStatusName(userStatus),
                            "userStatusCode" to userStatus,
                            "ageLower" to ageSignalsResult.ageLower(),
                            "ageUpper" to ageSignalsResult.ageUpper(),
                            "mostRecentApprovalDateMillis" to
                                ageSignalsResult.mostRecentApprovalDate()?.time,
                            "installId" to ageSignalsResult.installId(),
                            "checkedAtMillis" to System.currentTimeMillis()
                        )
                    )
                }
                .addOnFailureListener { exception ->
                    val ageSignalsException = exception as? AgeSignalsException
                    val errorCode = ageSignalsException?.getErrorCode()
                    result.success(
                        mapOf(
                            "success" to false,
                            "supported" to true,
                            "shouldBlockAccess" to false,
                            "errorCode" to errorCode,
                            "errorName" to ageSignalsErrorName(errorCode),
                            "message" to (exception.message ?: "Play Age Signals request failed."),
                            "checkedAtMillis" to System.currentTimeMillis()
                        )
                    )
                }
        } catch (exception: Exception) {
            result.success(
                mapOf(
                    "success" to false,
                    "supported" to true,
                    "shouldBlockAccess" to false,
                    "errorName" to "AGE_SIGNALS_UNAVAILABLE",
                    "message" to (exception.message ?: "Play Age Signals is unavailable."),
                    "checkedAtMillis" to System.currentTimeMillis()
                )
            )
        }
    }

    private fun ageSignalsStatusName(status: Int?): String? {
        return when (status) {
            null -> null
            AgeSignalsVerificationStatus.VERIFIED -> "VERIFIED"
            AgeSignalsVerificationStatus.SUPERVISED -> "SUPERVISED"
            AgeSignalsVerificationStatus.SUPERVISED_APPROVAL_PENDING ->
                "SUPERVISED_APPROVAL_PENDING"
            AgeSignalsVerificationStatus.SUPERVISED_APPROVAL_DENIED ->
                "SUPERVISED_APPROVAL_DENIED"
            AgeSignalsVerificationStatus.UNKNOWN -> "UNKNOWN"
            AgeSignalsVerificationStatus.DECLARED -> "DECLARED"
            else -> "UNRECOGNIZED_$status"
        }
    }

    private fun ageSignalsErrorName(errorCode: Int?): String? {
        return when (errorCode) {
            null -> null
            AgeSignalsErrorCode.API_NOT_AVAILABLE -> "API_NOT_AVAILABLE"
            AgeSignalsErrorCode.PLAY_STORE_NOT_FOUND -> "PLAY_STORE_NOT_FOUND"
            AgeSignalsErrorCode.NETWORK_ERROR -> "NETWORK_ERROR"
            AgeSignalsErrorCode.PLAY_SERVICES_NOT_FOUND -> "PLAY_SERVICES_NOT_FOUND"
            AgeSignalsErrorCode.CANNOT_BIND_TO_SERVICE -> "CANNOT_BIND_TO_SERVICE"
            AgeSignalsErrorCode.PLAY_STORE_VERSION_OUTDATED -> "PLAY_STORE_VERSION_OUTDATED"
            AgeSignalsErrorCode.PLAY_SERVICES_VERSION_OUTDATED ->
                "PLAY_SERVICES_VERSION_OUTDATED"
            AgeSignalsErrorCode.CLIENT_TRANSIENT_ERROR -> "CLIENT_TRANSIENT_ERROR"
            AgeSignalsErrorCode.APP_NOT_OWNED -> "APP_NOT_OWNED"
            AgeSignalsErrorCode.SDK_VERSION_OUTDATED -> "SDK_VERSION_OUTDATED"
            AgeSignalsErrorCode.INTERNAL_ERROR -> "INTERNAL_ERROR"
            else -> "UNKNOWN_ERROR_$errorCode"
        }
    }

    private fun installApk(path: String): String? {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            return null
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
            return "unknown_sources_settings_opened"
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            apkFile
        )

        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("", apkUri)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }

        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("", apkUri)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(fallbackIntent)
        }
        return "installer_opened"
    }
}
