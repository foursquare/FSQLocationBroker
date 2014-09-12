//
//  FSQLocationBroker.m
//
//  Copyright (c) 2014 foursquare. All rights reserved.
//

#import "FSQLocationBroker.h"

static void *kLocationBrokerLocationSubscriberKVOContext = &kLocationBrokerLocationSubscriberKVOContext;
static void *kLocationBrokerRegionMonitoringSubscriberKVOContext = &kLocationBrokerRegionMonitoringSubscriberKVOContext;

// Helper functions for code readability and reuse
BOOL applicationIsBackgrounded();
BOOL subscriberShouldRunInBackground(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberShouldReceiveLocationUpdates(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberShouldReceiveErrors(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberWantsContinuousLocation(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberWantsSLCMonitoring(NSObject<FSQLocationSubscriber> *locationSubscriber);

@interface FSQLocationBroker ()

// Publicly exposed as readonly
@property (atomic, readwrite) NSSet *locationSubscribers;
@property (atomic, readwrite) NSSet *regionSubscribers;

// Private
@property (nonatomic) CLLocationManager *locationManager;
@property (nonatomic) BOOL isMonitoringSignificantLocation, isUpdatingLocation;
@property (nonatomic) dispatch_queue_t serialQueue;

@end

@implementation FSQLocationBroker

static Class sharedInstanceClass = nil;

+ (void)setSharedClass:(Class)locationBrokerSubclass {
    if ([locationBrokerSubclass isSubclassOfClass:[FSQLocationBroker class]]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sharedInstanceClass = locationBrokerSubclass;
        });
    }
    else {
        NSAssert(0, @"Attempting to assign location broker shared class with class that does not subclass FSQLocationBroker (%@)", [locationBrokerSubclass description]);
    }
}

+ (instancetype)shared {  
    static FSQLocationBroker *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (sharedInstanceClass && sharedInstanceClass != [self class]) {
            sharedInstance = [sharedInstanceClass shared];
        }
        else {
            sharedInstance = [self new];
        }
    });
    return sharedInstance;
}

+ (BOOL)isAuthorized {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];
    return (authStatus == kCLAuthorizationStatusAuthorizedAlways
            || authStatus == kCLAuthorizationStatusAuthorizedWhenInUse);
#else
    return ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized);
#endif
}

- (id)init {
    if ((self = [super init])) {
        self.locationManager = [CLLocationManager new];
        self.locationManager.delegate = self;

        self.locationSubscribers = [NSMutableSet new];
        self.regionSubscribers = [NSMutableSet new];
        self.isMonitoringSignificantLocation = NO;
        self.isUpdatingLocation = NO;
        
        self.serialQueue = dispatch_queue_create("LocationBrokerSubscriberMutations", DISPATCH_QUEUE_SERIAL);
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)removeAllSubscribers {
    dispatch_async(self.serialQueue, ^{
        for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
            [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(desiredAccuracy))];
            [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(locationSubscriberOptions))];
        }
        
        for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
            [regionSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(monitoredRegions))];
        }
        
        self.locationSubscribers = [NSSet new];
        self.regionSubscribers = [NSSet new];
        
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager stopUpdatingLocation];
        
        for (CLRegion *region in self.locationManager.monitoredRegions) {
            [self.locationManager stopMonitoringForRegion:region];
        }
        
        for (CLBeaconRegion *region in self.locationManager.rangedRegions) {
            [self.locationManager stopRangingBeaconsInRegion:region];
        }
    });
}

- (CLLocation *)currentLocation {
    return self.locationManager.location;
}

- (CLLocationAccuracy)currentAccuracy {
    return self.locationManager.desiredAccuracy;
}

#pragma mark LocationSubscribers

- (void)addLocationSubscriber:(NSObject<FSQLocationSubscriber> *)locationSubscriber {
    dispatch_async(self.serialQueue, ^{
        if (![self.locationSubscribers containsObject:locationSubscriber]) {
            self.locationSubscribers = [self.locationSubscribers setByAddingObject:locationSubscriber];
            [locationSubscriber addObserver:self
                                 forKeyPath:NSStringFromSelector(@selector(desiredAccuracy))
                                    options:0
                                    context:kLocationBrokerLocationSubscriberKVOContext];
            [locationSubscriber addObserver:self
                                 forKeyPath:NSStringFromSelector(@selector(locationSubscriberOptions))
                                    options:0
                                    context:kLocationBrokerLocationSubscriberKVOContext];
            [self refreshLocationSubscribers];
        }
    });
}

- (void)removeLocationSubscriber:(NSObject<FSQLocationSubscriber> *)locationSubscriber {
    dispatch_async(self.serialQueue, ^{
        if ([self.locationSubscribers containsObject:locationSubscriber]) {
            [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(desiredAccuracy))];
            [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(locationSubscriberOptions))];
            
            NSMutableSet *mutableLocationSubscribers = [self.locationSubscribers mutableCopy];
            [mutableLocationSubscribers removeObject:locationSubscriber];
            self.locationSubscribers = [mutableLocationSubscribers copy];
        }
    });
}

- (BOOL)shouldMonitorSignificantLocationChanges {
    
    BOOL isBackgrounded = applicationIsBackgrounded();
    
    for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
        if (subscriberWantsSLCMonitoring(locationSubscriber)
            && (!isBackgrounded || subscriberShouldRunInBackground(locationSubscriber))) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)shouldUpdateLocations {

    BOOL isBackgrounded = applicationIsBackgrounded();
    
    for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
        if (subscriberWantsContinuousLocation(locationSubscriber) 
            && (!isBackgrounded || subscriberShouldRunInBackground(locationSubscriber))) {
            return YES;
        }
    }
    
    return NO;
}

- (CLLocationAccuracy)finestGrainAccuracy {
    
    BOOL isBackgrounded = applicationIsBackgrounded();
    
    NSSet *locationUpdatingSubscribers = [self.locationSubscribers objectsPassingTest:^BOOL(NSObject<FSQLocationSubscriber> *locationSubscriber, BOOL *stop) {
        return (subscriberWantsContinuousLocation(locationSubscriber) 
                && (!isBackgrounded || subscriberShouldRunInBackground(locationSubscriber)));
    }];
    
    if ([locationUpdatingSubscribers count] > 0) {
        CLLocationAccuracy lowestAccuracy = kCLLocationAccuracyThreeKilometers;
        for (NSObject<FSQLocationSubscriber> *locationSubscriber in locationUpdatingSubscribers) {
            if (locationSubscriber.desiredAccuracy < lowestAccuracy) {
                lowestAccuracy = locationSubscriber.desiredAccuracy;
            }
        }
        return lowestAccuracy;
    }
    else {
        return kCLLocationAccuracyThreeKilometers;
    }
}

- (void)refreshLocationSubscribers {
    CLLocationAccuracy newAccuracy = [self finestGrainAccuracy];
    if (self.locationManager.desiredAccuracy != newAccuracy) {
        self.locationManager.desiredAccuracy = newAccuracy;
    }
    
    /**
     We don't compare against our current state for these ifs because of worries that our state could get
     out of sync with the CLLocationManager's state (which we can't introspect). Telling it to start/stop when it
     already is in that state just no-ops so we always call.
     */
    
    // Should be monitoring
    if ([self shouldMonitorSignificantLocationChanges]) {
        [self.locationManager startMonitoringSignificantLocationChanges];
        self.isMonitoringSignificantLocation = YES;
        
    }
    // Should not be monitoring
    else {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        self.isMonitoringSignificantLocation = NO;
    }
    
    // Should be updating locations
    if ([self shouldUpdateLocations]) {
        [self.locationManager startUpdatingLocation];
        self.isUpdatingLocation = YES;
    }
    // Should not be updating locations
    else {
        [self.locationManager stopUpdatingLocation];
        self.isUpdatingLocation = NO;
    }
}

#pragma mark RegionMonitoringSubscribers


- (void)addRegionMonitoringSubscriber:(NSObject<FSQRegionMonitoringSubscriber> *)regionSubscriber {
    dispatch_async(self.serialQueue, ^{
        if (![self.regionSubscribers containsObject:regionSubscriber]) {
            self.regionSubscribers = [self.regionSubscribers setByAddingObject:regionSubscriber];
            [regionSubscriber addObserver:self
                               forKeyPath:NSStringFromSelector(@selector(monitoredRegions))
                                  options:0
                                  context:kLocationBrokerRegionMonitoringSubscriberKVOContext];
            [self refreshRegionMonitoringSubscribers];
        }
    });
}

- (void)removeRegionMonitoringSubscriber:(NSObject<FSQRegionMonitoringSubscriber> *)regionSubscriber {
    dispatch_async(self.serialQueue, ^{
        if ([self.regionSubscribers containsObject:regionSubscriber]) {
            [regionSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(monitoredRegions))];
            [self refreshRegionMonitoringSubscribers];
            
            NSMutableSet *mutableRegionSubscribers = [self.regionSubscribers mutableCopy];
            [mutableRegionSubscribers removeObject:regionSubscriber];
            self.regionSubscribers = [mutableRegionSubscribers copy];
        }
    });
}

- (void)refreshRegionMonitoringSubscribers {
    [self verifyMonitoredRegionIdentifiers];
    NSMutableSet *subscriberRegions = [self subscriberMonitoredRegions].mutableCopy;
    
    // Only remove unmonitored regions
    NSMutableSet *unmonitored = self.locationManager.monitoredRegions.mutableCopy;
    [unmonitored minusSet:subscriberRegions];
    for (CLRegion *region in unmonitored) {
        [self.locationManager stopMonitoringForRegion:region];
    }
    
    // Don't remonitor already monitored regions
    [subscriberRegions minusSet:self.locationManager.monitoredRegions];
    for (CLRegion *newRegion in subscriberRegions) {
        [self.locationManager startMonitoringForRegion:newRegion];
    }
}

// We use these methods to sync and reassign regions to a subscriber

- (void)verifyMonitoredRegionIdentifiers {
#if !NS_BLOCK_ASSERTIONS
    for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
        NSSet *regions = regionSubscriber.monitoredRegions;
        for (CLRegion *region in regions) {
            NSAssert([region.identifier hasPrefix:[regionSubscriber subscriberIdentifier]],
                     @"Subscriber: %@ monitors region without a matching prefix. (Region id: %@)",
                     [regionSubscriber class],
                     region.identifier);
        }
    }
#endif
}

- (NSSet *)subscriberMonitoredRegions {
    NSMutableSet *subscriberRegions = [NSMutableSet set];
    for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
        [subscriberRegions unionSet:regionSubscriber.monitoredRegions];
    }
    return subscriberRegions;
}

- (void)reassignMonitoredRegionsToSubscribers {
    NSMutableDictionary *subscribersByIdentifier = [NSMutableDictionary dictionary];
    
    for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
        subscribersByIdentifier[[regionSubscriber subscriberIdentifier]] = regionSubscriber;
    }
    
    for (CLRegion *region in self.locationManager.monitoredRegions) {
        NSString *identifier = [region.identifier componentsSeparatedByString:@"+"][0];
        NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber = subscribersByIdentifier[identifier];
        [regionSubscriber addMonitoredRegion:region];
    }
}

#pragma mark CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    BOOL isBackgrounded = applicationIsBackgrounded();
    
    for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
        if (subscriberShouldReceiveLocationUpdates(locationSubscriber)
            && (!isBackgrounded || subscriberShouldRunInBackground(locationSubscriber))) {
            
            [locationSubscriber locationManagerDidUpdateLocations:locations];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    BOOL isBackgrounded = applicationIsBackgrounded();
    
    for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
        if (subscriberShouldReceiveErrors(locationSubscriber)
            && (!isBackgrounded || subscriberShouldRunInBackground(locationSubscriber))) {
            [locationSubscriber locationManagerFailedWithError:error];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    // Our CLLocationManager.monitoredRegions has come out of sync with our subscriber monitored Regions.
    // Recalculate and monitor the regions for each subscriber.
    if (![manager.monitoredRegions isEqualToSet:[self subscriberMonitoredRegions]]) {
        [self reassignMonitoredRegionsToSubscribers];
    }
    
    for (id<FSQRegionMonitoringSubscriber> regionSubscriber in self.regionSubscribers) {
        if ([regionSubscriber.monitoredRegions containsObject:region]) {
            [regionSubscriber didEnterRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    // Our CLLocationManager.monitoredRegions has come out of sync with our subscriber monitored Regions.
    // Recalculate and monitor the regions for each subscriber.
    if (![manager.monitoredRegions isEqualToSet:[self subscriberMonitoredRegions]]) {
        [self reassignMonitoredRegionsToSubscribers];
    }
    
    for (id<FSQRegionMonitoringSubscriber> regionSubscriber in self.regionSubscribers) {
        if ([regionSubscriber.monitoredRegions containsObject:region]) {
            [regionSubscriber didExitRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    for (id<FSQRegionMonitoringSubscriber> regionSubscriber in self.regionSubscribers) {
        if (regionSubscriber.shouldReceiveRegionMonitoringErrors 
            && [regionSubscriber respondsToSelector:@selector(monitoringDidFailForRegion:withError:)]
            && [regionSubscriber.monitoredRegions containsObject:region]) {
            [regionSubscriber monitoringDidFailForRegion:region withError:error];
        }
    }
}

#pragma mark - Backgrounding -

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    // Refresh so it will drop non-background enabled subscribers from accounting
    [self refreshLocationSubscribers];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Refresh so it will re-account for non-background enabled subscribers
    [self refreshLocationSubscribers];
}

#pragma mark - Authorization -

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000

- (void)requestWhenInUseAuthorization {
    // Guard against users on iOS 7 and earlier
    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];        
    }
}

- (void)requestAlwaysAuthorization {
    // Guard against users on iOS 7 and earlier
    if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
        [self.locationManager requestAlwaysAuthorization];        
    }
}

#endif

#pragma mark - KVO callbacks -

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == kLocationBrokerLocationSubscriberKVOContext) {
        [self refreshLocationSubscribers];
    }
    else if (context == kLocationBrokerRegionMonitoringSubscriberKVOContext) {
        [self refreshRegionMonitoringSubscribers];
    }
}

@end

BOOL applicationIsBackgrounded() {
    return ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
}

BOOL subscriberShouldRunInBackground(NSObject<FSQLocationSubscriber> *locationSubscriber) {
    return (locationSubscriber.locationSubscriberOptions & FSQLocationSubscriberShouldRunInBackground);
}

BOOL subscriberShouldReceiveLocationUpdates(NSObject<FSQLocationSubscriber> *locationSubscriber) {
    return (locationSubscriber.locationSubscriberOptions & (FSQLocationSubscriberShouldRequestContinuousLocation 
                                                            | FSQLocationSubscriberShouldMonitorSLCs 
                                                            | FSQLocationSubscriberShouldReceiveAllBrokerLocations));
}

BOOL subscriberShouldReceiveErrors(NSObject<FSQLocationSubscriber> *locationSubscriber) {
    return ((locationSubscriber.locationSubscriberOptions & FSQLocationSubscriberShouldReceiveErrors)
            && [locationSubscriber respondsToSelector:@selector(locationManagerFailedWithError:)]);
}

BOOL subscriberWantsContinuousLocation(NSObject<FSQLocationSubscriber> *locationSubscriber) {
    return (locationSubscriber.locationSubscriberOptions & FSQLocationSubscriberShouldRequestContinuousLocation);
}

BOOL subscriberWantsSLCMonitoring(NSObject<FSQLocationSubscriber> *locationSubscriber) {
    return (locationSubscriber.locationSubscriberOptions & FSQLocationSubscriberShouldMonitorSLCs);
}
