import Cocoa
import FlutterMacOS
import HotKey
import Carbon

public class HotkeyManagerMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var _eventSink: FlutterEventSink?
    
    var hotKeyDict: Dictionary<String, HotKey> = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.leanflutter.plugins/hotkey_manager", binaryMessenger: registrar.messenger)
        let instance = HotkeyManagerMacosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "dev.leanflutter.plugins/hotkey_manager_event", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self._eventSink = events
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self._eventSink = nil
        return nil
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "register":
            register(call, result: result)
            break
        case "unregister":
            unregister(call, result: result)
            break
        case "unregisterAll":
            unregisterAll(call, result: result)
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func register(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "BAD_ARGS", message: "register: arguments must be a map", details: nil))
            return
        }

        // Flutter encodes Dart int as NSNumber (Int64); extract as UInt32 via NSNumber.
        guard let keyCodeNumber = args["keyCode"] as? NSNumber else {
            result(FlutterError(code: "BAD_KEY", message: "register: keyCode missing or wrong type", details: nil))
            return
        }
        let keyCode = keyCodeNumber.uint32Value

        // modifiers may be nil/NSNull when the list is empty — default to [].
        let modifiers: Array<String> = (args["modifiers"] as? Array<String>) ?? []

        guard let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "BAD_ID", message: "register: identifier missing", details: nil))
            return
        }

        guard let key = Key(carbonKeyCode: keyCode) else {
            result(FlutterError(code: "BAD_KEYCODE", message: "register: unknown carbonKeyCode \(keyCode)", details: nil))
            return
        }

        let hotKey: HotKey = HotKey(
            key: key,
            modifiers: NSEvent.ModifierFlags.init(pluginModifiers: modifiers)
        )
        let argsCopy = args
        hotKey.keyDownHandler = {
            guard let eventSink = self._eventSink else { return }
            eventSink(["type": "onKeyDown", "data": argsCopy] as NSDictionary)
        }
        hotKey.keyUpHandler = {
            guard let eventSink = self._eventSink else { return }
            eventSink(["type": "onKeyUp", "data": argsCopy] as NSDictionary)
        }
        self.hotKeyDict[identifier] = hotKey
        result(true)
    }
    
    public func unregister(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args:[String: Any] = call.arguments as! [String: Any]
        
        let identifier = args["identifier"] as! String
        
        self.hotKeyDict[identifier] = nil;
        
        result(true)
    }
    
    public func unregisterAll(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.hotKeyDict.removeAll();
        result(true)
    }
}
