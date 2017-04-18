//
//  FSQTestingHelper.m
//  FSQLocationBroker
//
//  Created by Eric Bueno on 4/18/17.
//  Copyright © 2017 Foursquare. All rights reserved.
//

#import "FSQTestingHelper.h"

@implementation FSQTestingHelper

#pragma mark - Coordinates

+ (CLLocationCoordinate2D)pennStationCoordinates {
    return CLLocationCoordinate2DMake(40.7506, -73.9935);
}

+ (CLLocationCoordinate2D)empireStateBuildingCoordinates {
    return CLLocationCoordinate2DMake(40.7484, -73.9857);
}

+ (CLLocationCoordinate2D)foursquareNYCCoordinates {
    return CLLocationCoordinate2DMake(40.7592, -73.9846);
}

+ (CLLocationCoordinate2D)sfCoordinates {
    return CLLocationCoordinate2DMake(37.7749, -122.4194);
}

@end
