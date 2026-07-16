import Foundation

/// The only constants compiled into the V2 app and Finder extension.
/// Legacy command URLs, root monitoring, scripts, and destructive actions stay
/// outside target membership.
enum Constants {
  static var appGroupID: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "RCMAppGroup") as? String,
      !value.isEmpty,
      !value.contains("$("),
      !value.hasPrefix(".")
    else {
      return "group.com.rightmenu.master"
    }
    return value
  }

  static var urlScheme: String {
    guard
      let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        as? [[String: Any]],
      let schemes = urlTypes.first?["CFBundleURLSchemes"] as? [String],
      let scheme = schemes.first,
      !scheme.isEmpty,
      !scheme.contains("$(")
    else {
      return "rightmenumaster"
    }
    return scheme
  }
}
