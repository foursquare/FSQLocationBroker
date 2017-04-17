//
//  FSQCurrentLocationTests.m
//  FSQCurrentLocationTests
//
//  Created by Eric Bueno on 4/17/17.
//  Copyright © 2017 Foursquare. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "FSQLocationBroker.h"

#import <CoreLocation/CoreLocation.h>

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
    
    CLLocationCoordinate2D pennStationCoordinates = CLLocationCoordinate2DMake(40.7484, -73.9857);
    CLLocationCoordinate2D empireStateBuildingCoordinates = CLLocationCoordinate2DMake(40.7484, -73.9857);
    CLLocationCoordinate2D foursquareNYCCoordinates = CLLocationCoordinate2DMake(40.7592, -73.9846);

    self.location1 = [[CLLocation alloc] initWithCoordinate:pennStationCoordinates altitude:0 horizontalAccuracy:125 verticalAccuracy:0 timestamp:beforeFutureDate];
    self.location2 = [[CLLocation alloc] initWithCoordinate:empireStateBuildingCoordinates altitude:0 horizontalAccuracy:65 verticalAccuracy:0 timestamp:futureDate];
    self.location3 = [[CLLocation alloc] initWithCoordinate:foursquareNYCCoordinates altitude:0 horizontalAccuracy:5 verticalAccuracy:0 timestamp:afterFutureDate];
}

- (void)tearDown {
    self.locationBroker = nil;

    [super tearDown];
}

- (void)testCurrentLocationWithInOrderDates {
    NSComparisonResult result;
    
    NSArray<CLLocation *> *locations = @[self.location1, self.location2, self.location3];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithOutOfOrderDates {
    NSComparisonResult result;

    NSArray<CLLocation *> *locations = @[self.location3, self.location1, self.location2];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithReverseDates {
    NSComparisonResult result;

    NSArray<CLLocation *> *locations = @[self.location3, self.location2, self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithInOrderDatesMultipleCalls {
    NSComparisonResult result;

    NSArray<CLLocation *> *locations1 = @[self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations1];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location1.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations2 = @[self.location2];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations2];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location2.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations3 = @[self.location3];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations3];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithOutOfOrderDatesMultipleCalls  {
    NSComparisonResult result;

    NSArray<CLLocation *> *locations2 = @[self.location2];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations2];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location2.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations3 = @[self.location3];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations3];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations1 = @[self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations1];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithReverseDatesMultipleCalls {
    NSComparisonResult result;

    NSArray<CLLocation *> *locations3 = @[self.location3];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations3];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations2 = @[self.location2];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations2];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
    
    NSArray<CLLocation *> *locations1 = @[self.location1];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations1];
    
    result = [self.locationBroker.currentLocation.timestamp compare:self.location3.timestamp];
    XCTAssert(result == NSOrderedSame, @"expected most recent location");
}

- (void)testCurrentLocationWithSameTimestamp {
    CLLocationCoordinate2D sfCoordinates = CLLocationCoordinate2DMake(37.7749, -122.4194);
    CLLocation *sfLocation = [[CLLocation alloc] initWithCoordinate:sfCoordinates altitude:self.location1.altitude horizontalAccuracy:self.location1.horizontalAccuracy verticalAccuracy:self.location1.verticalAccuracy timestamp:self.location1.timestamp];
    
    NSArray<CLLocation *> *locations3 = @[self.location1, sfLocation];
    
    [self.locationBroker locationManager:self.locationManger didUpdateLocations:locations3];
    
    XCTAssertEqual(self.locationBroker.currentLocation.coordinate.latitude, self.location1.coordinate.latitude, @"expected latitude from first processed location");
    XCTAssertEqual(self.locationBroker.currentLocation.coordinate.longitude, self.location1.coordinate.longitude, @"expected longitude from first processed location");
}

@end
