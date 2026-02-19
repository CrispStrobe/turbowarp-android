#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Registers the Swift FileSavePlugin with Capacitor's Objective-C bridge
// so it is exposed as window.Capacitor.Plugins.FileSave in the WebView.
CAP_PLUGIN(FileSavePlugin, "FileSave",
    CAP_PLUGIN_METHOD(saveFile, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openFile, CAPPluginReturnPromise);
)
