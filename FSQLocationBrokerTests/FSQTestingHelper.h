//
//  FSQTestingHelper.h
//  FSQLocationBroker
//
//  Created by Eric Bueno on 4/18/17.
//  Copyright © 2017 Foursquare. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreLocation/CoreLocation.h>

#pragma mark Date Equality Macros

#define FSQAssertEqualDates(date1, date2) \
    XCTAssert([date1 isKindOfClass:[NSDate class]], @"date1 should be a NSDate"); \
    XCTAssert([date2 isKindOfClass:[NSDate class]], @"date2 should be a NSDate"); \
    XCTAssert([date1 compare:date2] == NSOrderedSame, @"%@ does not equal %@", date1, date2);

#define FSQAssertNotEqualDates(date1, date2) \
    XCTAssert([date1 isKindOfClass:[NSDate class]], @"date1 should be a NSDate"); \
    XCTAssert([date2 isKindOfClass:[NSDate class]], @"date2 should be a NSDate"); \
    XCTAssert([date1 compare:date2] != NSOrderedSame, @"%@ does equal %@", date1, date2);

#pragma mark Coordinate Equality Macros

#define FSQAssertEqualCoordinates(coordinate1, coordinate2) \
    XCTAssert(coordinate1.latitude == coordinate2.latitude, @"latitude: %@ does not equal %@", @(coordinate1.latitude), @(coordinate2.latitude)); \
    XCTAssert(coordinate1.longitude == coordinate2.longitude, @"longitude: %@ does not equal %@", @(coordinate1.longitude), @(coordinate2.longitude));

#define FSQAssertNotEqualCoordinates(coordinate1, coordinate2) \
    XCTAssert(coordinate1.latitude != coordinate2.latitude, @"latitude: %@ does equal %@", @(coordinate1.latitude), @(coordinate2.latitude)); \
    XCTAssert(coordinate1.longitude != coordinate2.longitude, @"longitude: %@ does equal %@", @(coordinate1.longitude), @(coordinate2.longitude));

@interface FSQTestingHelper : NSObject

#pragma mark - Coordinates

+ (CLLocationCoordinate2D)pennStationCoordinates;

+ (CLLocationCoordinate2D)empireStateBuildingCoordinates;

+ (CLLocationCoordinate2D)foursquareNYCCoordinates;

+ (CLLocationCoordinate2D)sfCoordinates;

@end
