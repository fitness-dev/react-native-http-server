//
//  HttpServer.swift
//  RNHttpServer
//
//  Created by Nicolas Martinez on 4/29/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation

enum WebServerManagerError: Error {
  case completionNotFound;
}

class EventEmitter {
  
  /// Shared Instance.
  public static var sharedInstance = EventEmitter()
  
  // ReactNativeEventEmitter is instantiated by React Native with the bridge.
  private static var eventEmitter: WebServerManager!
  
  private init() {}
  
  // When React Native instantiates the emitter it is registered here.
  func registerEventEmitter(eventEmitter: WebServerManager) {
    EventEmitter.eventEmitter = eventEmitter
  }
  
  func dispatch(name: String, body: Any?) {
    EventEmitter.eventEmitter.sendEvent(withName: name, body: body)
  }
  
  /// All Events which must be support by React Native.
  lazy var allEvents: [String] = {
    var allEventNames: [String] = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    
    // Append all events here
    
    return allEventNames
  }()
  
}


@objc(WebServerManager)
class WebServerManager: RCTEventEmitter {
  private enum ServerState {
    case Stopped
    case Running
  }
  
  private let webServer: GCDWebServer = GCDWebServer()
  private var serverRunning : ServerState =  ServerState.Stopped
  private var completionBlocks: NSMutableDictionary = NSMutableDictionary() ;
  
  override init(){
    super.init()
    EventEmitter.sharedInstance.registerEventEmitter(eventEmitter: self)
  }
  
  @objc static override func requiresMainQueueSetup() -> Bool {
    return true
  }
  
  override func supportedEvents() -> [String]! {
    return EventEmitter.sharedInstance.allEvents
  }
  
  /**
   Creates an NSError with a given message.
   
   - Parameter message: The error message.
   
   - Returns: An error including a domain, error code, and error      message.
   */
  private func createError(message: String)-> NSError {
    let error = NSError(domain: "app.domain", code: 0,userInfo: [NSLocalizedDescriptionKey: message])
    return error
  }
  
  
  @objc public func response(_ requestId: String, status: NSInteger, responseData data: String) {
    let completion = completionBlocks.value(forKey: requestId) as! GCDWebServerCompletionBlock?;
    if (completion != nil) {
      let response = GCDWebServerDataResponse(data: Data(data.data(using: .utf8)!), contentType: "application/json")
      completion!(response)
      completionBlocks.removeObject(forKey: requestId);
    } else {
      NSLog("A completion is attempted to be called twice. ");
    }
  }
  
  
  @objc public func subscribe(_ method: String) {
    webServer.addDefaultHandler(forMethod: method, request: GCDWebServerDataRequest.self) { (request, completionBlock) in
      let requestId = NSString(string: UUID().uuidString)
      let requestBodyData = (request as! GCDWebServerDataRequest).data;
      let requestBodyString = NSString(data: requestBodyData, encoding: String.Encoding.utf8.rawValue);
      self.completionBlocks.setObject(completionBlock, forKey: requestId)
      EventEmitter.sharedInstance.dispatch(name: method, body: [
        "requestId": requestId,
        "body": requestBodyString,
      ])
    }
  }
  
  /**
   Start `webserver` on the Main Thread
   - Returns:`Promise` to JS side, resolve the server URL and reject thrown errors
   */
  @objc public func startServer(_ port: NSInteger, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
    if (serverRunning == ServerState.Stopped) {
      DispatchQueue.main.sync {
        serverRunning = ServerState.Running
        webServer.start(withPort: UInt(port), bonjourName: "React Native Web Server")
        resolve(webServer.serverURL?.absoluteString)
      }
    } else {
      let errorMessage : String = "Server start failed"
      reject("0", errorMessage, createError(message:errorMessage))
    }
  }
  
  /**
   Stop `webserver` and update serverRunning variable to Stopped case
   */
  @objc public func stopServer(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
    if (serverRunning == ServerState.Running) {
      webServer.stop()
      serverRunning = ServerState.Stopped
    }
    resolve(true);
  }
  
  @objc public func isRunning(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
    resolve(serverRunning == ServerState.Running);
  }
  
}
