#import <Foundation/Foundation.h>
// Call off the main thread. Limited to one plain <=30s test clip.
NSDictionary *SubPopProbeAudio(NSData *xml, NSString *expectedUID, NSURL *outputDirectory);
