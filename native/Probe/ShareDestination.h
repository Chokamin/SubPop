#import <Foundation/Foundation.h>
#include <sys/types.h>

// The URL carries only an allowlisted host ID and a UUID. It never supplies a
// source/destination path and never launches or automates Final Cut Pro.
BOOL SubPopHandleShareDestinationURL(NSURL *URL, NSBundle *bundle, NSURL *bridgeURL);
int SubPopInstallSystemShareDestination(NSBundle *bundle, NSString *volumePath);

// Local filesystem core, exposed for native tests with isolated directories.
// Neither directory is accepted from a URL or from a shared project.
NSDictionary *SubPopInstallShareDestination(NSData *preset, NSURL *userDirectory,
                                          NSURL *systemDirectory, BOOL systemInstall);
NSDictionary *SubPopShareDestinationRequest(NSURL *URL);
BOOL SubPopShareDestinationDirectoryModeAllowed(NSString *path,uid_t owner,gid_t group,
                                               mode_t mode,BOOL final,BOOL resourceRead);
