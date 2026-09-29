#import <Foundation/Foundation.h>
// Call off the main thread. Limited to one plain <=30s test clip.
NSDictionary *SubPopProbeAudio(NSData *xml, NSString *expectedUID, NSURL *outputDirectory);
// Metadata only. The worker uses this to check a user-exported full timeline.
NSDictionary *SubPopAudioFileInfo(NSURL *url);
