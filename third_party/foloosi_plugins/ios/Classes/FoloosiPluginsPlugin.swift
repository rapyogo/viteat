import Flutter
import UIKit
import FoloosiSdk

public class FoloosiPluginsPlugin: NSObject, FlutterPlugin,FoloosiDelegate {

  var callBack: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "foloosi_plugins", binaryMessenger: registrar.messenger())
    let instance = FoloosiPluginsPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "init" {
      if let args = call.arguments as? Dictionary<String, Any>,
      let key = args["public_key"] as? String {
        let dictValue = convertToDictionary(text: key)
        let initData = InitData()
        initData.merchantKey = dictValue?["merchantKey"] as? String
        initData.customColor = dictValue?["customColor"] as? String
        FoloosiPay.initSDK(initData: initData, withDelegate: self)
      }
    } else if call.method == "makePayment" {
      callBack = result
      if let args = call.arguments as? Dictionary<String, Any>,
      let orderString = args["order_data"] as? String {
        let dictValue = convertToDictionary(text: orderString)
        let orderData = OrderData()
        orderData.currencyCode = dictValue?["currencyCode"] as? String
        orderData.orderAmount = dictValue?["orderAmount"] as? Double
        orderData.orderId = dictValue?["orderId"] as? String
        orderData.orderDescription = dictValue?["orderDescription"] as? String
        orderData.postalCode = dictValue?["postalCode"] as? String
        orderData.state = dictValue?["state"] as? String
        orderData.country = dictValue?["country"] as? String
        orderData.customerUniqueReference = dictValue?["customerUniqueReference"] as? String
        let customerobj = dictValue?["customer"] as? Dictionary<String,Any>
        let customer = Customer()
        customer.customerEmail = customerobj?["email"] as? String
        customer.customerName = customerobj?["name"] as? String
        customer.customerCity = customerobj?["city"] as? String
        customer.customerAddress = customerobj?["address"] as? String
        customer.customerPhoneCode = customerobj?["code"] as? String
        customer.customerPhoneNumber = customerobj?["mobile"] as? String
        orderData.customer = customer
        FoloosiPay.makePayment(orderData: orderData)
      }
    }else if call.method == "makePaymentWithReferenceToken" {
      callBack = result
      if let args = call.arguments as? Dictionary<String, Any>,
      let referenceToken = args["reference_token"] as? String {
        FoloosiPay.makePaymentWithReferenceToken(referenceToken)
      }
    }
    else if call.method == "setLogVisible" {
      if let args = call.arguments as? Dictionary<String, Any>,
      let debug = args["visible"] as? Bool {
        FLog.setLogVisible(debug: debug)
      }
    }
  }

  func convertToDictionary(text: String) -> [String: Any]? {

    if let data = text.data(using: .utf8) {
      do {
        return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
      } catch {
        print(error.localizedDescription)
      }
    }
    return nil
  }

  public func onPaymentError(descriptionOfError: String ,transactionId: String,responseCode: String) {
    let result = ["success" : false, "message" : descriptionOfError, "transaction_id": transactionId, "response_code": responseCode] as [String : Any]
    if let theJSONData = try? JSONSerialization.data(withJSONObject: result,options: []) {
      let theJSONText = String(data: theJSONData, encoding: .utf8)
      callBack!(theJSONText!)
    }
  }

  public func onPaymentSuccess(transactionId: String,responseCode: String) {
    let result = ["success" : true, "message" : "Payment Successful", "transaction_id": transactionId, "response_code": responseCode] as [String : Any]
    if let theJSONData = try? JSONSerialization.data(withJSONObject: result,options: []) {
      let theJSONText = String(data: theJSONData, encoding: .utf8)
      callBack!(theJSONText!)
    }
  }
}