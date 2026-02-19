#import <Foundation/Foundation.h>
// Use @import for Swift Package Manager compatibility (capacitor-swift-pm)
@import Capacitor;

// Registers the Swift FileSavePlugin with Capacitor's Objective-C bridge
// so it is exposed as window.Capacitor.Plugins.FileSave in the WebView.
CAP_PLUGIN(FileSavePlugin, "FileSave",
    CAP_PLUGIN_METHOD(saveFile, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openFile, CAPPluginReturnPromise);
)
