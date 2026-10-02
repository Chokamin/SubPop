#import <Foundation/Foundation.h>
// Call off the main thread. Limited to one plain <=30s test clip.
NSDictionary *SubPopProbeAudio(NSData *xml, NSString *expectedUID, NSURL *outputDirectory);
// Optional worker-selected source-channel components. Channels are 1-based,
// flattened in actual audio-track order, or local to the specified sourceID
// (a 1-based audio-source ordinal, never an AV trackID). Gain is linear amplitude. A nil/null
// components value requests the actual source's default downmix. Metadata
// expectations are per-track channel count and actual audio-track count.
NSDictionary *SubPopProbeAudioChannels(NSData *xml, NSString *expectedUID, NSURL *outputDirectory, NSDictionary *channelMix);
// Metadata only. The worker uses this to check a user-exported full timeline.
NSDictionary *SubPopAudioFileInfo(NSURL *url);
