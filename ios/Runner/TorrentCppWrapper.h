#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TorrentEventCallback)(NSString *json);

@interface TorrentCppWrapper : NSObject

- (instancetype)init;

- (BOOL)initializeSession:(nullable TorrentEventCallback)callback;
- (void)shutdownSession;

- (nullable NSString *)addMagnet:(NSString *)magnet
                        savePath:(NSString *)savePath
                          jobId:(NSString *)jobId;

- (nullable NSString *)addTorrentFile:(NSString *)filePath
                             savePath:(NSString *)savePath
                                jobId:(NSString *)jobId;

- (BOOL)pauseTorrent:(NSString *)jobId;
- (BOOL)resumeTorrent:(NSString *)jobId;
- (BOOL)removeTorrent:(NSString *)jobId deleteFiles:(BOOL)deleteFiles;

- (nullable NSString *)lastError;

@end

NS_ASSUME_NONNULL_END
