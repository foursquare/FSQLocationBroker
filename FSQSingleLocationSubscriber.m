//
//  FSQSingleLocationSubscriber.m
//
//  Copyright (c) 2014 foursquare. All rights reserved.
//

#import "FSQSingleLocationSubscriber.h"

@interface FSQSingleLocationSubscriber ()
@property (nonatomic) NSTimer *cutoffTimer;
@property (nonatomic) CLLocation *bestLocationReceived;
@property (nonatomic) NSDate *startTime;
@property (nonatomic) FSQLocationSubscriberOptions locationSubscriberOptions;
@end

@implementation FSQSingleLocationSubscriber

- (instancetype)initWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
              maximumAcceptableAccuracy:(CLLocationAccuracy)maximumAcceptableAccuracy
       maximumAcceptableLocationRecency:(NSTimeInterval)maximumAcceptableRecency
                             cutoffTime:(NSTimeInterval)cutoffTimeInterval
                  shouldRunInBackground:(BOOL)shouldRunInBackground
                           onCompletion:(FSQSingleLocSubCompletionBlock)onCompletion {

    if ((self = [super init])) {
        _desiredAccuracy = desiredAccuracy;
        _maximumAcceptableAccuracy = maximumAcceptableAccuracy;
        _onCompletion = [onCompletion copy];
        _cutoffTimeInterval = cutoffTimeInterval;
        _locationSubscriberOptions = (FSQLocationSubscriberShouldRequestContinuousLocation | FSQLocationSubscriberShouldReceiveErrors);
        if (shouldRunInBackground) {
            _locationSubscriberOptions |= FSQLocationSubscriberShouldRunInBackground;
        }
        else {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(applicationDidEnterBackground:)
                                                         name:UIApplicationDidEnterBackgroundNotification
                                                       object:nil];
        }
    }
    return self;
}


+ (instancetype)startWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
               maximumAcceptableAccuracy:(CLLocationAccuracy)maximumAcceptableAccuracy
        maximumAcceptableLocationRecency:(NSTimeInterval)maximumAcceptableRecency
                              cutoffTime:(NSTimeInterval)cutoffTimeInterval
                   shouldRunInBackground:(BOOL)shouldRunInBackground
                            onCompletion:(FSQSingleLocSubCompletionBlock)onCompletion {
    if (!onCompletion || !(cutoffTimeInterval > 0) || !(maximumAcceptableAccuracy > 0)) {
        NSAssert(0, @"FSQSimpleLocationSubscriber: Must include a completion block, cutoff time >0 and max accuracy > 0");
        return nil;
    }
    
    CLLocation *currentLocation = [FSQLocationBroker shared].currentLocation;
    
    if (currentLocation
        && (-[currentLocation.timestamp timeIntervalSinceNow] <= maximumAcceptableRecency)) {
        if (currentLocation.horizontalAccuracy <= maximumAcceptableAccuracy) {
            onCompletion(YES, currentLocation, nil, nil);
            return nil;
        }
    }
    else {
        currentLocation = nil;
    }
    
    FSQSingleLocationSubscriber *subscriber = [[self alloc] initWithDesiredAccuracy:desiredAccuracy
                                                          maximumAcceptableAccuracy:maximumAcceptableAccuracy
                                                   maximumAcceptableLocationRecency:maximumAcceptableRecency
                                                                         cutoffTime:cutoffTimeInterval
                                                              shouldRunInBackground:shouldRunInBackground
                                                                       onCompletion:onCompletion];
    
    [subscriber startListening];
    subscriber.bestLocationReceived = currentLocation;
    
    return subscriber;
}


- (void)startListening {
    self.bestLocationReceived = nil;
    self.startTime = [NSDate new];
    [[FSQLocationBroker shared] addLocationSubscriber:self];
    self.cutoffTimer = [NSTimer scheduledTimerWithTimeInterval:self.cutoffTimeInterval
                                                        target:self
                                                      selector:@selector(cutoffTimerFired:)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)stopListening {
    [self.cutoffTimer invalidate];
    self.cutoffTimer = nil;
    [[FSQLocationBroker shared] removeLocationSubscriber:self];
}

- (void)cancel {
    [self stopListening];
}

- (void)cutoffTimerFired:(NSTimer *)cutoffTimer {
    if (self.onCompletion) {
        self.onCompletion(NO, self.bestLocationReceived, @(-[self.startTime timeIntervalSinceNow]), nil);
    }
    [self stopListening];
}

- (BOOL)isListening {
    return self.cutoffTimer.isValid;
}

- (void)setShouldRunInBackground:(BOOL)shouldRunInBackground {
    if (shouldRunInBackground && !self.shouldRunInBackground) {
        self.locationSubscriberOptions |= FSQLocationSubscriberShouldRunInBackground;
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    else if (!shouldRunInBackground && self.shouldRunInBackground) {
        self.locationSubscriberOptions &= ~FSQLocationSubscriberShouldRunInBackground;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
}

- (BOOL)shouldRunInBackground {
    return ((self.locationSubscriberOptions & FSQLocationSubscriberShouldRunInBackground) == FSQLocationSubscriberShouldRunInBackground);
}

- (void)locationManagerDidUpdateLocations:(NSArray *)locations {
    for (CLLocation *location in locations) {
        if (location.horizontalAccuracy <= self.maximumAcceptableAccuracy) {
            if (self.onCompletion) {
                self.onCompletion(YES, location, @(-[self.startTime timeIntervalSinceNow]), nil);
            }
            [self stopListening];
            return;
        }
        else if (location.horizontalAccuracy < self.bestLocationReceived.horizontalAccuracy) {
            self.bestLocationReceived = location;
        }
    }
}

- (void)locationManagerFailedWithError:(NSError *)error {
    if (kCLErrorLocationUnknown != error.code) {
        if (self.onCompletion) {
            self.onCompletion(NO, self.bestLocationReceived, @(-[self.startTime timeIntervalSinceNow]), error);
        }
        [self stopListening];
    }
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    [self cutoffTimerFired:self.cutoffTimer];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.cutoffTimer invalidate];
    self.cutoffTimer = nil;
}

@end
