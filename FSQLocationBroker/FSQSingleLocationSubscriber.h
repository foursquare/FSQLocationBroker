//
//  FSQSingleLocationSubscriber.h
//
//  Copyright (c) 2014 foursquare. All rights reserved.
//

@import Foundation;
#import "FSQLocationBroker.h"

/**
 Callback block when the subscriber finds an acceptable location or times out or fails due to an error.
 
 @param didSucceed  YES if an acceptable location was found successfully, NO if there was a timeout or error
 @param location    A location matching the specifications you set or the location with the best horizontal 
                    accuracy that the subscriber was able to get within the cutoff time. 
 
                    This location will not be older the the requested maximumAcceptableRecency.
 @param elapsedTime The amount of time the subscriber took to get your location (boxed NSTimeInterval). 
                    If there was already an acceptable location on the broker and the block thus is being 
                    called synchronously, this value will be nil.
 @param error       The system location manager error if this block is being called due to an error, else nil.
 
 @see [CLLocationManagerDelegate locationManager:didFailWithError:]
 */
typedef void (^FSQSingleLocSubCompletionBlock)(BOOL didSucceed, CLLocation *location, NSNumber *elapsedTime, NSError *error);

/**
 This class is intended as a simple way to get a single location from the system.
 
 It has properties that define all the location information you should consider when trying to get/use a location.
 It uses FSQLocationBroker to try to find a location which matches your parameters and then return the result
 via a block.
 */
@interface FSQSingleLocationSubscriber : NSObject<FSQLocationSubscriber>

/**
 The accuracy to ask the system location manager for.
 */
@property (nonatomic, readonly) CLLocationAccuracy desiredAccuracy;

/**
 The first received location with a horizontal accuracy less than or equal to this value will stop the 
 subscriber and be returned via the completion block.
 */
@property (nonatomic, readonly) CLLocationAccuracy maximumAcceptableAccuracy;

/**
 If an acceptable location hasn't been received within this time, the subscriber
 will stop listening and call your completion block.
 */
@property (nonatomic, readonly) NSTimeInterval cutoffTimeInterval;

/**
 If YES, the subscriber will keep trying to get a location when backgrounded.
 May have not have the intended effect unless your app has background location entitlements.
 
 If NO, the subscriber will stop and call your completion block when the app is backgrounded.
 */
@property (nonatomic, readonly) BOOL shouldRunInBackground;

/**
 This block will be called with the first location the subscriber finds that
 meets your requirements. 
 
 If the subscriber does not receive an acceptable location within the
 cutoffTime you set it will send you the best accuracy location it could get in that time.
 
 This will also be called if the app is backgrounded before the subscriber could finish and
 shouldRunInBackground was not YES, or if the system location manager encounters an error.
 */
@property (nonatomic, readonly) FSQSingleLocSubCompletionBlock onCompletion;

/**
 True if this subscriber is currently listening for location updates.
 */
@property (nonatomic, readonly) BOOL isListening;

/**
 Will create a new single loc subscriber and start it listening for location updates
 As soon as it receives a location that meets the criteria you specify, it will
 stop listening for updates and pass the location to the callback you provide.
 
 @param desiredAccuracy 
            The accuracy to ask the system location manager for.
 @param maximumAcceptableAccuracy 
            The first received location with a horizontal accuracy less than or equal to this value will stop the 
            subscriber and be returned via the completion block.
 @param maximumAcceptableLocationRecency 
            If the location broker already has a location under your max accuracy
            it will immediately return if the location is no older than this time interval.
 @param cutoffTimeInterval
            If an acceptable location hasn't been received within this time, the subscriber
            will stop listening and call your completion block.
 @param shouldRunInBackground 
            If YES, the subscriber will keep trying to get a location when backgrounded.
            May have not have the intended effect unless your app has background location entitlements.
            If NO, the subscriber will stop and call your completion block when the app is backgrounded.
 @param onCompletion
            This block will be called with the first location the subscriber finds that
            meets your requirements. If the subscriber does not receive an acceptable location within the
            cutoffTime you set it will send you the best accuracy location it could get in that time.
            (for the most recent location, you should check FSLocationBroker instead).
            This will also be called if the app is backgrounded before the subscriber could finish and
            shouldRunInBackground was not YES, or if the system location manager encounters an error.
 
 @return A pointer to the subscriber instance if a location could not be sent synchronously.
         You do not have to do anything with this value, it will be retained automatically for you for the
         duration of the operation.
 
 @note You must provide an onCompletion block, a max accuracy > 0 and a
        cutoff time > 0 or this method will assert and return nil.
 
 @note If there is already an acceptable accuracy on the location broker, the completion block will be 
       called synchronously and this method will return nil.
 */
+ (instancetype)startWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
               maximumAcceptableAccuracy:(CLLocationAccuracy)maximumAcceptableAccuracy
        maximumAcceptableLocationRecency:(NSTimeInterval)maximumAcceptableRecency
                              cutoffTime:(NSTimeInterval)cutoffTimeInterval
                   shouldRunInBackground:(BOOL)shouldRunInBackground
                            onCompletion:(FSQSingleLocSubCompletionBlock)onCompletion;
/**
 Manually stop the subscriber listening for updates.
 
 There is no effect if the subscriber is not currently running.
 
 @note This will decerement the retain count of the subscriber if it was previously running. 
 If you are not retaining it yourself it may be released in the future.
 */
- (void)cancel;

@end
