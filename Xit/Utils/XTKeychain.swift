import Cocoa

final class XTKeychain: NSObject
{
  enum Error: Swift.Error
  {
    case invalidURL
    case itemNotFound
  }

  /// Gets a password using a URL's host, port and path.
  class func findPassword(url: URL, account: String) -> String?
  {
    guard let host = url.host
    else { return nil }
    
    return findPassword(host: host, path: url.path,
                        port: (url as NSURL).port?.uint16Value ?? 80,
                        account: account)
  }
  
  private class func passwordQuery(host: String, path: String,
                                   port: UInt16, account: String) -> CFDictionary
  {
    return [kSecClass: kSecClassInternetPassword,
            kSecAttrServer: host,
            kSecAttrPort: port,
            kSecAttrAccount: account,
            kSecReturnData: kCFBooleanTrue,
            ] as CFDictionary
  }
  
  /// Gets a password from the keychain.
  class func findPassword(host: String, path: String,
                          port: UInt16, account: String) -> String?
  {
    var item: CFTypeRef?
    let err = SecItemCopyMatching(passwordQuery(host: host, path: path,
                                                port: port, account: account),
                                  &item)
    
    guard err == errSecSuccess,
          let passwordData = item as? Data,
          let password = String(data: passwordData, encoding: .utf8)
    else { return nil }
    
    return password
  }
  
  class func findItem(url: URL, user: String) -> (String?, SecKeychainItem?)
  {
    guard let host = url.host
    else { return (nil, nil) }
    
    return findItem(host: host, path: url.path, port: UInt16(url.port ?? 0),
                    account: user)
  }
  
  class func findItem(host: String, path: String,
                      port: UInt16, account: String,
                      protocol: SecProtocolType = .HTTP,
                      authType: SecAuthenticationType = .httpBasic)
                      -> (String?, SecKeychainItem?)
  {
    var passwordLength: UInt32 = 0
    var passwordData: UnsafeMutableRawPointer?
    let nsHost: NSString = host as NSString
    let nsPath: NSString = path as NSString
    let nsAccount: NSString = account as NSString
    let item = UnsafeMutablePointer<SecKeychainItem?>.allocate(capacity: 1)
    
    let err = SecKeychainFindInternetPassword(
        nil,
        UInt32(nsHost.length), nsHost.utf8String,
        0, nil,
        UInt32(nsAccount.length), nsAccount.utf8String,
        UInt32(nsPath.length), nsPath.utf8String,
        port, .HTTP, .httpBasic,
        &passwordLength, &passwordData,
        item)
    
    guard err == noErr
    else { return (nil, nil) }
    
    return (NSString(bytes: passwordData!, length: Int(passwordLength),
                     encoding: String.Encoding.utf8.rawValue) as String?,
            item.pointee)
  }
  
  /// Saves a password to the keychain using a URL's host, port and path.
  class func savePassword(url: URL, account: String, password: String) throws
  {
    guard let host = url.host
    else { throw Error.invalidURL }
    
    try savePassword(host: host,
                     path: url.path,
                     port: UInt16(url.port ?? 80),
                     account: account,
                     password: password)
  }
  
  /// Saves a password to the keychain.
  class func savePassword(host: String, path: String,
                          port: UInt16, account: String,
                          password: String) throws
  {
    let err = SecItemAdd([kSecClass: kSecClassInternetPassword,
                          kSecAttrServer: host,
                          kSecAttrPort: port,
                          kSecAttrAccount: account,
                          kSecValueData: password,
                          ] as CFDictionary, nil)
    
    
    guard err == noErr
    else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: nil)
    }
  }
  
  class func changePassword(url: URL, account: String, password: String) throws
  {
    guard let host = url.host
    else { throw Error.invalidURL }
    
    try changePassword(host: host, path: url.path,
                       port: UInt16(url.port ?? 80),
                       account: account, password: password)
  }
  
  class func changePassword(host: String, path: String,
                            port: UInt16, account: String,
                            password: String) throws
  {
    let (resultPassword, resultItem) = findItem(host: host, path: path, port: port,
                                                account: account)
    guard let oldPassword = resultPassword,
          let item = resultItem
    else { throw Error.itemNotFound }
    guard oldPassword != password
    else { return }
    
    let nsPassword: NSString = password as NSString
    
    let err = SecKeychainItemModifyAttributesAndData(
        item, nil, UInt32(nsPassword.length), nsPassword.utf8String)
    
    guard err == noErr
    else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: nil)
    }
  }
}
