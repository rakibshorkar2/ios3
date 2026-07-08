#import "TorrentCppWrapper.h"
#import "LibtorrentNative.h"

@interface TorrentCppWrapper () {
    void *_session;
}

@property (nonatomic, copy, nullable) TorrentEventCallback eventCallback;

@end

static void EventCallbackTrampoline(const char *json, void *context) {
    TorrentCppWrapper *wrapper = (__bridge TorrentCppWrapper *)context;
    NSString *jsonString = [NSString stringWithUTF8String:json];
    if (jsonString) {
        [wrapper handleEvent:jsonString];
    }
}

@implementation TorrentCppWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = NULL;
#ifdef DEBUG
        NSLog(@"[TorrentCpp] Wrapper instance created");
#endif
    }
    return self;
}

- (void)dealloc {
    [self shutdownSession];
}

#pragma mark - Session

- (BOOL)initializeSession:(nullable TorrentEventCallback)callback {
    if (_session) {
#ifdef DEBUG
        NSLog(@"[TorrentCpp] Session already initialized, skipping");
#endif
        return YES;
    }

    self.eventCallback = callback;

#ifdef DEBUG
    NSLog(@"[TorrentCpp] Calling tryagi_libtorrent_session_create...");
#endif

    int code = tryagi_libtorrent_session_create(
        EventCallbackTrampoline,
        (__bridge void *)self,
        &_session
    );

    if (code != 0 || !_session) {
        const char *err = tryagi_libtorrent_last_error(NULL);
        NSLog(@"[TorrentCpp] Session create failed: code=%d, error=%s", code, err ?: "null");
        _session = NULL;
        return NO;
    }

#ifdef DEBUG
    NSLog(@"[TorrentCpp] Session initialized successfully (session=%p)", _session);
#endif
    return YES;
}

- (void)shutdownSession {
    if (_session) {
#ifdef DEBUG
        NSLog(@"[TorrentCpp] Destroying session %p", _session);
#endif
        tryagi_libtorrent_session_destroy(_session);
        _session = NULL;
#ifdef DEBUG
        NSLog(@"[TorrentCpp] Session destroyed");
#endif
    }
    self.eventCallback = nil;
}

#pragma mark - Job Control

- (nullable NSString *)addMagnet:(NSString *)magnet
                        savePath:(NSString *)savePath
                          jobId:(NSString *)jobId {
    if (!_session) {
#ifdef DEBUG
        NSLog(@"[TorrentCpp] addMagnet rejected: no active session");
#endif
        return nil;
    }

    NSString *escapedMagnet = [self escapeJSON:magnet];
    NSString *escapedPath = [self escapeJSON:savePath];

    NSString *json = [NSString stringWithFormat:
        @"{\"input\":{\"jobId\":\"%@\",\"magnetUri\":\"%@\",\"torrentData\":null,\"torrentFileName\":null,\"downloadDirectory\":\"file://%@\",\"rateLimits\":null},\"selection\":null}",
        jobId,
        escapedMagnet,
        escapedPath
    ];

#ifdef DEBUG
    NSLog(@"[TorrentCpp] addMagnet: jobId=%@, jsonPayloadLength=%lu", jobId, (unsigned long)json.length);
#endif

    int code = tryagi_libtorrent_job_start(_session, json.UTF8String);
    if (code != 0) {
        NSString *err = [self lastError];
        NSLog(@"[TorrentCpp] addMagnet failed: code=%d, error=%@", code, err ?: @"unknown");
        return nil;
    }

#ifdef DEBUG
    NSLog(@"[TorrentCpp] addMagnet submitted: jobId=%@", jobId);
#endif
    return jobId;
}

- (nullable NSString *)addTorrentFile:(NSString *)filePath
                             savePath:(NSString *)savePath
                                jobId:(NSString *)jobId {
    if (!_session) {
#ifdef DEBUG
        NSLog(@"[TorrentCpp] addTorrentFile rejected: no active session");
#endif
        return nil;
    }

    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (!fileData) {
        NSLog(@"[TorrentCpp] Cannot read torrent file at path: %@", filePath);
        return nil;
    }

    NSString *base64 = [fileData base64EncodedStringWithOptions:0];
    NSString *fileName = [filePath lastPathComponent];

#ifdef DEBUG
    NSLog(@"[TorrentCpp] addTorrentFile: file=%@, size=%lu, base64Length=%lu",
          fileName, (unsigned long)fileData.length, (unsigned long)base64.length);
#endif

    NSString *json = [NSString stringWithFormat:
        @"{\"input\":{\"jobId\":\"%@\",\"magnetUri\":null,\"torrentData\":\"%@\",\"torrentFileName\":\"%@\",\"downloadDirectory\":\"file://%@\",\"rateLimits\":null},\"selection\":null}",
        jobId,
        base64,
        [self escapeJSON:fileName],
        [self escapeJSON:savePath]
    ];

    int code = tryagi_libtorrent_job_start(_session, json.UTF8String);
    if (code != 0) {
        NSString *err = [self lastError];
        NSLog(@"[TorrentCpp] addTorrentFile failed: code=%d, error=%@", code, err ?: @"unknown");
        return nil;
    }

#ifdef DEBUG
    NSLog(@"[TorrentCpp] addTorrentFile submitted: jobId=%@", jobId);
#endif
    return jobId;
}

- (BOOL)pauseTorrent:(NSString *)jobId {
    if (!_session) return NO;

    NSString *json = [NSString stringWithFormat:@"{\"jobId\":\"%@\"}", jobId];

#ifdef DEBUG
    NSLog(@"[TorrentCpp] pauseTorrent: jobId=%@", jobId);
#endif

    int code = tryagi_libtorrent_job_pause(_session, json.UTF8String);
    if (code != 0) {
        NSLog(@"[TorrentCpp] pauseTorrent failed: code=%d", code);
    }
    return code == 0;
}

- (BOOL)resumeTorrent:(NSString *)jobId {
    if (!_session) return NO;

    NSString *json = [NSString stringWithFormat:@"{\"jobId\":\"%@\"}", jobId];

#ifdef DEBUG
    NSLog(@"[TorrentCpp] resumeTorrent: jobId=%@", jobId);
#endif

    int code = tryagi_libtorrent_job_resume(_session, json.UTF8String);
    if (code != 0) {
        NSLog(@"[TorrentCpp] resumeTorrent failed: code=%d", code);
    }
    return code == 0;
}

- (BOOL)removeTorrent:(NSString *)jobId deleteFiles:(BOOL)deleteFiles {
    if (!_session) return NO;

    NSString *json;
    if (deleteFiles) {
        json = [NSString stringWithFormat:@"{\"jobId\":\"%@\",\"deleteFiles\":true}", jobId];
    } else {
        json = [NSString stringWithFormat:@"{\"jobId\":\"%@\"}", jobId];
    }

#ifdef DEBUG
    NSLog(@"[TorrentCpp] removeTorrent: jobId=%@, deleteFiles=%d", jobId, deleteFiles);
#endif

    int code = tryagi_libtorrent_job_cancel(_session, json.UTF8String);
    if (code != 0) {
        NSLog(@"[TorrentCpp] removeTorrent failed: code=%d", code);
    }
    return code == 0;
}

#pragma mark - Error

- (nullable NSString *)lastError {
    const char *err = tryagi_libtorrent_last_error(_session);
    if (!err) return nil;
    return [NSString stringWithUTF8String:err];
}

#pragma mark - Event Handling

- (void)handleEvent:(NSString *)json {
#ifdef DEBUG
    NSLog(@"[TorrentCpp] Event received: %@", json.length > 200 ? [[json substringToIndex:200] stringByAppendingString:@"..."] : json);
#endif
    TorrentEventCallback cb = self.eventCallback;
    if (cb) {
        cb(json);
    }
}

#pragma mark - JSON Helpers

- (NSString *)escapeJSON:(NSString *)value {
    if (!value) return @"";
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\t" withString:@"\\t" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

@end
