//
//  FSQCurrentLocationTests.m
//  FSQCurrentLocationTests
//
//  Created by Eric Bueno on 4/17/17.
//  Copyright © 2017 Foursquare. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "FSQLocationBroker.h"
#import "FSQTestingHelper.h"

@interface FSQCurrentLocationTests : XCTestCase

@property (nonatomic, strong, readwrite) FSQLocationBroker *locationBroker;

@property (nonatomic, strong, readwrite) CLLocationManager *locationManger;

@property (nonatomic, strong, readwrite) CLLocation *location1;
@property (nonatomic, strong, readwrite) CLLocation *location2;
@property (nonatomic, strong, readwrite) CLLocation *location3;

@end

@implementation FSQCurrentLocationTests

- (void)setUp {
    [super setUp];
    
    self.locationBroker = [[FSQLocationBroker alloc] init];
    
    self.locationManger = [[CLLocationManager alloc] init];
    
    NSDate *futureDate = [NSDate dateWithTimeIntervalSinceNow:3600];
    NSDate *beforeFutureDate = [futureDate dateByAddingTimeInterval:-100];
    NSDate *afterFutureDate = [futureDate dateByAddingTimeInterval:603];
    
    self.location1 = [[CLLocation alloc] initWithCoordinate:[FSQTestingHelper pennStationCoordinates] altitude:0 horizontalAccuracy:125 verticalAccuracy:0 timestamp:beforeFutureDate];
    self.location2 = [[CLLocation alloc] initWithCoordinate:[FSQTestingHelper empireStateBuildingCoordinates] altitude:0 horizontalAccuracy:65 verticalAccuracy:0 timestamp:futureDate];
    self.location3 = [[CLLocation alloc] initWithCoordinate:[FSQTestingHelper foursquareNYCCoordinates] altitude:0 horizontalAccuracy:5 verticalAccuracy:0 timestamp:afterFutureDate];
}

- (void)tearDown {
    self.locationBroker = nil;

    [super tearDown];
}

- (void)testDateEqualityMacros {
    NSDate *date1 = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    NSDate *otherDate1 = [date1 dateByAddingTimeInterval:0];
    NSDate *date2 = [date1 dateByAddingTimeInterval:1];
    
    // Test same object
    FSQAssertEqualDates(date1, date1);
    
    // Test same dates
    FSQAssertEqualDates(date1, otherDate1);
    
    FSQAssertNotEqualDates(date1, date2);
}

- (void)testCoordinateEqualityMacros {
    CLLocationCoordinate2D coordinate1 = [FSQTestingHelper foursquareNYCCoordinates];
    CLLocationCoordinate2D otherCoordinate1 = [FSQTestingHelper foursquareNYCCoordinates];
    CLLocationCoordinate2D coordinate2 = [FSQTestingHelper sfCoordinates];
    
    // Test same struct
    FSQAssertEqualCoordinates(coordinate1, coordinate1);
    
    // Test same coordinates
    FSQAssertEqualCoordinates(coordinate1, otherCoordinate1);
    
    FSQAssertNotEqualCoordinates(coordinate1, coordinate2);
}

- (void)testCurrentLocationWithInOrderDates {
    NSArray<CLLocation *> *locations = @[self.location1, self.location2, self.location3];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    // Expected most recent location
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location3.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location3.coordinate);
}

- (void)testCurrentLocationWithOutOfOrderDates {
    NSArray<CLLocation *> *locations = @[self.location2, self.location3, self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    // Expected most recent location
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location3.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location3.coordinate);
}

- (void)testCurrentLocationWithReverseDates {
    NSArray<CLLocation *> *locations = @[self.location3, self.location2, self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    // Expected most recent location
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location3.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location3.coordinate);
}

- (void)testCurrentLocationIsOverwrittenWithNewerLocation {
    // Expected to overwrite current location with location1
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:@[self.location1]];
    
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location1.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location1.coordinate);
    
    // Expected to overwrite current location with location2
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:@[self.location2]];
    
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location2.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location2.coordinate);
}

- (void)testCurrentLocationIsNotOverwrittenWithOlderLocation  {
    // Expected to overwrite current location with location3
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:@[self.location3]];
    
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location3.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location3.coordinate);

    // Expected NOT to overwrite current location
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:@[self.location1]];
    
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location3.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location3.coordinate);
}

/**
 *  When 2 locations have the same timestamps, the winner is
 *  determined by which location is processed first
 *
 */
- (void)testCurrentLocationWithSameTimestamp {
    CLLocation *sfLocation = [[CLLocation alloc] initWithCoordinate:[FSQTestingHelper sfCoordinates] altitude:self.location1.altitude horizontalAccuracy:self.location1.horizontalAccuracy verticalAccuracy:self.location1.verticalAccuracy timestamp:self.location1.timestamp];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations: @[self.location1, sfLocation]];
    
    // Expected first processed location
    FSQAssertEqualDates(self.locationBroker.currentLocation.timestamp, self.location1.timestamp);
    FSQAssertEqualCoordinates(self.locationBroker.currentLocation.coordinate, self.location1.coordinate);
}

@end
