package com.foloosi.foloosi_plugins

import androidx.annotation.NonNull;
import android.content.Context
import com.foloosi.core.FPayListener
import com.foloosi.core.FoloosiLog
import com.foloosi.core.FoloosiPay
import com.foloosi.models.InitData
import com.foloosi.models.OrderData
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import org.json.JSONObject
import io.flutter.plugin.common.MethodChannel.Result


/** FoloosiPluginsPlugin */
class FoloosiPluginsPlugin : FlutterPlugin, MethodCallHandler, FPayListener, ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var result: MethodChannel.Result

    private var context: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "foloosi_plugins")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "init" -> {
                    val initDataObj: String = call.argument<String>("public_key").toString()
                    FoloosiPay.init(
                        context,
                        getGSONObj().fromJson(initDataObj, InitData::class.java)
                    )
                }

                "makePayment" -> {
                    this.result = result
                    val orderObj: String = call.argument<String>("order_data").toString()
                    FoloosiPay.setPaymentListener(this)
                    FoloosiPay.makePayment(getGSONObj().fromJson(orderObj, OrderData::class.java))
                }

                "makePaymentWithReferenceToken" -> {
                    this.result = result
                    val referenceToken: String = call.argument<String>("reference_token").toString()
                    FoloosiPay.setPaymentListener(this)
                    FoloosiPay.makePaymentWithReferenceToken(referenceToken)
                }

                "setLogVisible" -> FoloosiLog.setLogVisible(
                    call.argument<String>("visible").toString().toBoolean()
                )

                else -> result.notImplemented()
            }
        } catch (e: java.lang.Exception) {
            e.printStackTrace()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // Viteat : les TODO() d origine levaient NotImplementedError et faisaient
    // planter l app a chaque recreation de l activite (rotation, theme...).
    override fun onDetachedFromActivity() {
        context = null
    }

    override fun onAttachedToActivity(@NonNull binding: ActivityPluginBinding) {
        context = binding.activity;
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        context = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        context = null
    }

    fun getGSONObj(): Gson {
        return GsonBuilder().create()
    }

    override fun onTransactionSuccess(transactionId: String, responseCode: String) {
        sendCallBack(true, transactionId, "Payment Success", responseCode);
    }

    override fun onTransactionFailure(error: String, transactionId: String, responseCode: String) {
        sendCallBack(false, transactionId, error, responseCode);
    }

    override fun onTransactionCancelled(responseCode: String) {
        sendCallBack(false, "", "Payment Cancelled", responseCode);
    }

    private fun sendCallBack(
        success: Boolean,
        transactionId: String,
        message: String,
        responseCode: String
    ) {
        try {
            if (result != null) {
                val jsonObj = JSONObject()
                jsonObj.put("success", success)
                jsonObj.put("message", message)
                jsonObj.put("transaction_id", transactionId)
                jsonObj.put("response_code", responseCode)
                result.success(jsonObj.toString())
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
