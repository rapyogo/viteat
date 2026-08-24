class FlexPay {
  bool? enable;
  String? merchantCode;
  String? name;
  String? image;
  String? currency;

  FlexPay({this.enable, this.merchantCode, this.name, this.image, this.currency});

  FlexPay.fromJson(Map<String, dynamic> json) {
    enable = json['enable'];
    merchantCode = json['merchantCode'];
    name = json['name'];
    image = json['image'];
    currency = json['currency'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['enable'] = enable;
    data['merchantCode'] = merchantCode;
    data['name'] = name;
    data['image'] = image;
    data['currency'] = currency;
    return data;
  }
}
