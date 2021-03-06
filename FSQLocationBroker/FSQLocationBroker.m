//
//  FSQLocationBroker.m
//
//  Copyright (c) 2014 foursquare. All rights reserved.
//

#import "FSQLocationBroker.h"
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

static void *kLocationBrokerLocationSubscriberKVOContext = &kLocationBrokerLocationSubscriberKVOContext;
static void *kLocationBrokerRegionMonitoringSubscriberKVOContext = &kLocationBrokerRegionMonitoringSubscriberKVOContext;
static void *kLocationBrokerVisitSubscriberKVOContext = &kLocationBrokerVisitSubscriberKVOContext;

// Helper functions for code readability and reuse
BOOL applicationIsBackgrounded(void);
BOOL subscriberShouldRunInBackground(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberShouldReceiveLocationUpdates(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberShouldReceiveErrors(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberWantsContinuousLocation(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberWantsSLCMonitoring(NSObject<FSQLocationSubscriber> *locationSubscriber);
BOOL subscriberWantsVisitMonitoring(NSObject<FSQVisitMonitoringSubscriber> *locationSubscriber);

@interface FSQLocationBroker ()

// Publicly exposed as readonly
@property (atomic, readwrite) NSSet *locationSubscribers;
@property (atomic, readwrite) NSSet *regionSubscribers;
@property (atomic, readwrite) NSSet *visitSubscribers;
@property (atomic, copy, nullable) CLLocation *currentLocation;

// Private
@property (nonatomic) CLLocationManager *locationManager;
@property (nonatomic) BOOL isMonitoringSignificantLocation, isUpdatingLocation, isMonitoringVisits;
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
            sharedInstance = [[self alloc] init];
        }
    });
    return sharedInstance;
}

+ (BOOL)isAuthorized {
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];
    return (authStatus == kCLAuthorizationStatusAuthorizedAlways
            || authStatus == kCLAuthorizationStatusAuthorizedWhenInUse);
}

- (instancetype)init {
    if ((self = [super init])) {
        self.locationManager = [CLLocationManager new];
        
        self.currentLocation = self.locationManager.location;
        self.locationManager.delegate = self;

        self.locationSubscribers = [NSSet new];
        self.regionSubscribers = [NSSet new];
        self.visitSubscribers = [NSSet new];
        
        self.isMonitoringSignificantLocation = NO;
        self.isUpdatingLocation = NO;
        self.isMonitoringVisits = NO;
        
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
            @try {
                [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(desiredAccuracy))];
            } @catch (NSException * __unused exception) {}
            @try {
                [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(locationSubscriberOptions))];
            } @catch (NSException * __unused exception) {}
        }
        
        for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
            @try {
                [regionSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(monitoredRegions))];
            } @catch (NSException * __unused exception) {}
        }
        
        self.locationSubscribers = [NSSet new];
        self.regionSubscribers = [NSSet new];
        self.visitSubscribers = [NSSet new];
        
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager stopUpdatingLocation];
        
        [self.locationManager stopMonitoringVisits];
        
        for (CLRegion *region in self.locationManager.monitoredRegions) {
            [self.locationManager stopMonitoringForRegion:region];
        }
        
        for (CLBeaconRegion *region in self.locationManager.rangedRegions) {
            [self.locationManager stopRangingBeaconsInRegion:region];
        }
    });
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
            @try {
                [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(desiredAccuracy))];
            } @catch (NSException * __unused exception) {}
            @try {
                [locationSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(locationSubscriberOptions))];
            } @catch (NSException * __unused exception) {}
            
            NSMutableSet *mutableLocationSubscribers = [self.locationSubscribers mutableCopy];
            [mutableLocationSubscribers removeObject:locationSubscriber];
            self.locationSubscribers = [mutableLocationSubscribers copy];
            
            [self refreshLocationSubscribers];
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

- (BOOL)shouldAllowBackgroundLocationUpdates {
    NSArray *backgroundModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
    BOOL backgroundLocationModeEnabled = [backgroundModes containsObject:@"location"];
    BOOL hasBackgroundLocationPermission = ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedAlways);
    
    BOOL subscriberWantsBackgroundLocationUpdates = NO;
    for (NSObject<FSQLocationSubscriber> *locationSubscriber in self.locationSubscribers) {
        if (subscriberWantsContinuousLocation(locationSubscriber) && subscriberShouldRunInBackground(locationSubscriber)) {
            subscriberWantsBackgroundLocationUpdates = YES;
            break;
        }
    }
    
    return backgroundLocationModeEnabled && hasBackgroundLocationPermission && subscriberWantsBackgroundLocationUpdates;
}

- (BOOL)shouldMonitorVisits {
    
    for (NSObject<FSQVisitMonitoringSubscriber> *locationSubscriber in self.visitSubscribers) {
        if (subscriberWantsVisitMonitoring(locationSubscriber)) {
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
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [self refreshLocationSubscribers];
        });
        return;
    }
    
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
    
    // Should allow background location
    if (@available(iOS 9.0, *)) {
        self.locationManager.allowsBackgroundLocationUpdates = [self shouldAllowBackgroundLocationUpdates];
    }
}

#pragma mark RegionMonitoringSubscribers


- (void)addRegionMonitoringSubscriber:(NSObject<FSQRegionMonitoringSubscriber> *)regionSubscriber {
    dispatch_async(self.serialQueue, ^{
        if (![self.regionSubscribers containsObject:regionSubscriber]) {
            
            NSString *subscriberIdentifier = [regionSubscriber subscriberIdentifier];
            
            for (CLRegion *region in self.locationManager.monitoredRegions) {
                NSString *identifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];
                if ([identifier isEqualToString:subscriberIdentifier]) {
                    [regionSubscriber addMonitoredRegion:region];
                }
            }

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
            @try {
                [regionSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(monitoredRegions))];
            } @catch (NSException * __unused exception) {}
            
            NSMutableSet *mutableRegionSubscribers = [self.regionSubscribers mutableCopy];
            [mutableRegionSubscribers removeObject:regionSubscriber];
            self.regionSubscribers = [mutableRegionSubscribers copy];
            
            [self refreshRegionMonitoringSubscribersRemovingSubscriberWithIdentifer:[regionSubscriber subscriberIdentifier]
                                                  shouldRemoveAllUnmonitoredRegions:NO];
        }
    });
}


- (void)refreshRegionMonitoringSubscribers {
    [self refreshRegionMonitoringSubscribersRemovingSubscriberWithIdentifer:nil
                                          shouldRemoveAllUnmonitoredRegions:NO];
}

- (void)refreshRegionMonitoringSubscribersRemovingSubscriberWithIdentifer:(nullable NSString *)subscriberIdentifier 
                                        shouldRemoveAllUnmonitoredRegions:(BOOL)shouldRemoveAllUnmonitoredRegions {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [self refreshRegionMonitoringSubscribersRemovingSubscriberWithIdentifer:subscriberIdentifier
                                                  shouldRemoveAllUnmonitoredRegions:shouldRemoveAllUnmonitoredRegions];
        });
        return;
    }
    
    [self verifyMonitoredRegionIdentifiers];
    NSMutableSet *allCurrentSubscriberRegions = [self subscriberMonitoredRegions].mutableCopy;
    NSDictionary *allSubscribersByIdentifier = [self subscribersByIdentifier];
    
    NSSet *allSubscriberRegionIdentifiers = [allCurrentSubscriberRegions valueForKey:NSStringFromSelector(@selector(identifier))];
    
    NSSet *unmonitoredRegions = [self.locationManager.monitoredRegions objectsPassingTest:^BOOL(CLRegion *evaluatedObject, BOOL *stop) {
        return ![allSubscriberRegionIdentifiers containsObject:[evaluatedObject identifier]]; 
    }];
    
    for (CLRegion *region in unmonitoredRegions) {
        NSString *regionsSubscriberIdentifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];

        /*
         Only remove unmonitored regions with subscriber ids we know about, or are for the subscriber we are removing
         
         Do not remove unmonitoried regions with unrecognized subscriber ids, as those subscribers may be added
         later and we want to resync them.

         Also do not remove regions without valid locbroker identifiers, as they may have been added separately
         via some non locbroker code path (since monitored region set is shared by all instances of CLLocationManager)
         */
        if (shouldRemoveAllUnmonitoredRegions
            || (regionsSubscriberIdentifier
                && (allSubscribersByIdentifier[regionsSubscriberIdentifier] != nil
                    || [regionsSubscriberIdentifier isEqualToString:subscriberIdentifier]))) {
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
    
    NSSet *currentlyMonitoringRegionIdentifiers = [self.locationManager.monitoredRegions valueForKey:NSStringFromSelector(@selector(identifier))];
    
    // Don't remonitor already monitored regions
    NSSet *regionsThatNeedMonitoring = [allCurrentSubscriberRegions objectsPassingTest:^BOOL(CLRegion *evaluatedObject, BOOL *stop) {
        return ![currentlyMonitoringRegionIdentifiers containsObject:[evaluatedObject identifier]];
    }];
    
    for (CLRegion *newRegion in regionsThatNeedMonitoring) {
        [self.locationManager startMonitoringForRegion:newRegion];
    }
}

- (void)forceSyncRegionMonitorSubscribersWithSystem {
    [self refreshRegionMonitoringSubscribersRemovingSubscriberWithIdentifer:nil 
                                          shouldRemoveAllUnmonitoredRegions:YES];
}

- (void)verifyMonitoredRegionIdentifiers {
#if !NS_BLOCK_ASSERTIONS
 
    for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
        NSString *correctPrefix = [[regionSubscriber subscriberIdentifier] stringByAppendingString:@"+"];
        
        NSSet *regions = regionSubscriber.monitoredRegions;
        for (CLRegion *region in regions) {
            NSAssert([region.identifier hasPrefix:correctPrefix],
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

- (NSDictionary *)subscribersByIdentifier {
    NSMutableDictionary *subscribersByIdentifier = [NSMutableDictionary dictionary];
    
    for (NSObject<FSQRegionMonitoringSubscriber> *regionSubscriber in self.regionSubscribers) {
        subscribersByIdentifier[[regionSubscriber subscriberIdentifier]] = regionSubscriber;
    }

    return [subscribersByIdentifier copy];
}

- (nullable NSString *)subscriberIdentifierFromRegionIdentifier:(NSString *)regionIdentifier {
    NSArray *identifierComponents = [regionIdentifier componentsSeparatedByString:@"+"];
    if (identifierComponents.count > 1) {
        return [identifierComponents firstObject];
    }
    else {
        // Not a valid location broker identifier
        return nil;
    }
}

- (void)requestStateForRegion:(CLRegion *)region {
    [self.locationManager requestStateForRegion:region];
}

#pragma mark VisitSubscriber

- (void)addVisitSubscriber:(NSObject<FSQVisitMonitoringSubscriber> *)visitSubscriber {
    dispatch_async(self.serialQueue, ^{
        if (![self.visitSubscribers containsObject:visitSubscriber]) {
            self.visitSubscribers = [self.visitSubscribers setByAddingObject:visitSubscriber];
            
            [visitSubscriber addObserver:self
                                 forKeyPath:NSStringFromSelector(@selector(shouldMonitorVisits))
                                    options:0
                                    context:kLocationBrokerVisitSubscriberKVOContext];
            
            [self refreshVisitSubscribers];
        }
    });
}

- (void)removeVisitSubscriber:(NSObject<FSQVisitMonitoringSubscriber> *)visitSubscriber {
    dispatch_async(self.serialQueue, ^{
        if ([self.visitSubscribers containsObject:visitSubscriber]) {
            @try {
                [visitSubscriber removeObserver:self forKeyPath:NSStringFromSelector(@selector(shouldMonitorVisits))];
            } @catch (NSException * __unused exception) {}
            
            NSMutableSet *mutableVisitSubscribers = [self.visitSubscribers mutableCopy];
            [mutableVisitSubscribers removeObject:visitSubscriber];
            self.visitSubscribers = [mutableVisitSubscribers copy];
            
            [self refreshVisitSubscribers];
        }
    });
}

- (void)refreshVisitSubscribers {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [self refreshVisitSubscribers];
        });
        return;
    }
    
    if ([self shouldMonitorVisits]) {
        [self.locationManager startMonitoringVisits];
        self.isMonitoringVisits = YES;
    }
    else {
        [self.locationManager stopMonitoringVisits];
        self.isMonitoringVisits = NO;
    }
}

#pragma mark CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    BOOL isBackgrounded = applicationIsBackgrounded();
    CLLocation *newestLocation = nil;
    for (CLLocation *location in locations) {
        if (!newestLocation ||
            [newestLocation.timestamp earlierDate:location.timestamp] == newestLocation.timestamp) {
            newestLocation = location;
        }
    }
    
    self.currentLocation = newestLocation;
    
    
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
    
    NSString *regionsSubscriberIdentifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];
    
    if (regionsSubscriberIdentifier) {
        NSDictionary *subscribersByIdentifier = [self subscribersByIdentifier];
        id<FSQRegionMonitoringSubscriber> regionSubscriber = subscribersByIdentifier[regionsSubscriberIdentifier];
        if (regionSubscriber) {
            [regionSubscriber didEnterRegion:region];
        }
        else {
            // This region's subscriber is not registered, so we should stop monitoring it.
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    NSString *regionsSubscriberIdentifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];
    
    if (regionsSubscriberIdentifier) {
        NSDictionary *subscribersByIdentifier = [self subscribersByIdentifier];
        id<FSQRegionMonitoringSubscriber> regionSubscriber = subscribersByIdentifier[regionsSubscriberIdentifier];
        if (regionSubscriber) {
            [regionSubscriber didExitRegion:region];
        }
        else {
            // This region's subscriber is not registered, so we should stop monitoring it.
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    NSString *regionsSubscriberIdentifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];
    
    if (regionsSubscriberIdentifier) {
        NSDictionary *subscribersByIdentifier = [self subscribersByIdentifier];
        id<FSQRegionMonitoringSubscriber> regionSubscriber = subscribersByIdentifier[regionsSubscriberIdentifier];
        if (regionSubscriber
            && [regionSubscriber respondsToSelector:@selector(didDetermineState:forRegion:)]) {
            [regionSubscriber didDetermineState:state forRegion:region];
        }
        else {
            // This region's subscriber is not registered, so we should stop monitoring it.
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(nullable CLRegion *)region withError:(NSError *)error {
    NSString *regionsSubscriberIdentifier = [self subscriberIdentifierFromRegionIdentifier:region.identifier];
    
    if (regionsSubscriberIdentifier) {
        NSDictionary *subscribersByIdentifier = [self subscribersByIdentifier];
        id<FSQRegionMonitoringSubscriber> regionSubscriber = subscribersByIdentifier[regionsSubscriberIdentifier];
        if (regionSubscriber) {
            if (regionSubscriber.shouldReceiveRegionMonitoringErrors
                && [regionSubscriber respondsToSelector:@selector(monitoringDidFailForRegion:withError:)]) {
                [regionSubscriber monitoringDidFailForRegion:region withError:error];
            }
        }
        else {
            // This region's subscriber is not registered, so we should stop monitoring it.
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didVisit:(CLVisit *)visit {
    
    for (NSObject<FSQVisitMonitoringSubscriber> *visitSubscriber in self.visitSubscribers) {
        if (subscriberWantsVisitMonitoring(visitSubscriber)) {
            
            [visitSubscriber locationManagerDidVisit:visit];
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
    
    if ([[self class] isAuthorized]) {
        self.currentLocation = self.locationManager.location;
    }
}

#pragma mark - Authorization -

- (void)requestWhenInUseAuthorization {
    [self.locationManager requestWhenInUseAuthorization];
}

- (void)requestAlwaysAuthorization {
    [self.locationManager requestAlwaysAuthorization];
}

#pragma mark - KVO callbacks -

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary *)change
                       context:(nullable void *)context {
    if (context == kLocationBrokerLocationSubscriberKVOContext) {
        [self refreshLocationSubscribers];
    }
    else if (context == kLocationBrokerRegionMonitoringSubscriberKVOContext) {
        [self refreshRegionMonitoringSubscribers];
    }
    else if (context == kLocationBrokerVisitSubscriberKVOContext) {
        [self refreshVisitSubscribers];
    }
}

@end

BOOL applicationIsBackgrounded() {

#if defined(FSQ_IS_APP_EXTENSION)
    return NO;
#else
    return ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
#endif

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

BOOL subscriberWantsVisitMonitoring(NSObject<FSQVisitMonitoringSubscriber> *locationSubscriber) {
    return locationSubscriber.shouldMonitorVisits;
}

NS_ASSUME_NONNULL_END
