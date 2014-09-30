FSQLocationBroker
=================

A centralized location manager for your app.

Overview
========
FSQLocationBroker sits between the other classes of your app and CoreLocation's CLLocationManager, giving you a centralized place to manage location services in your app. The broker uses a list of location subscribers to determine which services to request from the system and then forwards the data back where appropriate.

This repo also includes the FSQSingleLocationSubscriber class, a helper that works with the broker for the common case where you only need to get a single location. 

Both these classes are thoroughly documented in their headers (which should be automatically parsed and available through Xcode's documentation popovers), but this file includes a brief overview of their features.

Note: A test project is included but it is used for build testing only - an example application is currently not included in this repository.

Setup
=====
FSQLocationBroker has no dependencies other than Foundation and CoreLocation. Simply add the files to your project and you are ready to go.

If you would like to use a custom subclass of FSQLocationBroker in your app, you should set your subclass's class using the `setSharedClass:` method early on in your app life cycle, before the broker singleton is created (like in your app delegate's `application:didFinishLaunchingWithOptions:`).

To get location data in your class, implement either the FSQLocationSubscriber or FSQRegionMonitoringSubscriber protocols as approriate and add your class to the broker's subscriber list.


Location Subscribers
====================
If your class is interested in getting location callbacks from the broker, it should implement the FSQLocationSubscriber protocol, then add itself to the subscriber list using `addLocationSubscriber:`

Your subscriber can define what sorts of location information it is interested in using the **locationSubscriberOptions** bitmask property. The broker will then request the correct services from its CLLocationManager based on what all of its subscribers need.

Region Monitoring Subscribers
=============================
If your class is interested in region monitoring (geofences) it should implement the FSQRegionMonitoringSubscriber protocol, then add itself to the subscriber list using `addRegionMonitoringSubscriber:`

Your subscriber can define a list of regions it would like to monitor and the broker will take care of requesting them from the system for you. Your subscriber should also define an identifer string and include that in its region's identifiers so that the broker can re-assign the regions from CLLocationManager back to your class after an app restart (see the header documentation for more information).

Broker Methods and Properties
=============================
You can access the shared pointer singleton for the location broker via the `shared` method. If you want to use a custom subclass of FSQLocationBroker in your app, you should first set your subclass's class by calling the `setSharedClass:` method on the base FSQLocationBroker. This will cause the base implementation of `[FSQLocationBroker shared]` to forward onto the `shared` method of the class you specify and avoid creating multiple singletons.

You can add location or region monitoring subscribers to the broker using the following methods:
```objc
- (void)addLocationSubscriber:(NSObject<FSQLocationSubscriber> *)locationSubscriber;
- (void)removeLocationSubscriber:(NSObject<FSQLocationSubscriber> *)locationSubscriber
- (void)addRegionMonitoringSubscriber:(NSObject<FSQRegionMonitoringSubscriber> *)regionSubscriber
- (void)removeRegionMonitoringSubscriber:(NSObject<FSQRegionMonitoringSubscriber> *)regionSubscriber
```

You can then get the list of subscribers via the **locationSubscribers** and **regionSubscribers** properties. The same class can implement both subscriber protocols, but it must add itself to both subscriber lists independently.

The **currentLocation** property returns the most recent location received by the CLLocationManager. In most cases if you are interested in getting only a single location, you should use FSQSingleLocationSubscriber instead of accessing this property directly.

See the comments in FSQLocationBroker.h for more in depth documentation.

FSQSingleLocationSubscriber
===========================
This subscriber class acts as a helper for when you just need to get a single location. You pass in the accuracy you want to request from the system, the maximum acceptable accuracy that you want from the location returned, how recent the location has to be, and how long to try to get this location. It takes care of adding itself to the broker, finding, and returning an acceptable location to you. 

See the comments in FSQSingleLocationSubscriber.h for more in depth documentation.

Contributors
============
The classes were initially developed by Foursquare Labs for internal use. 

FSQLocationBroker was originally written by Anoop Ranganath ([@anoopr](https://twitter.com/anoopr)) with major contributions by Adam Alix ([@adamalix](https://twitter.com/adamalix)). It is currently maintained by Brian Dorfman ([@bdorfman](https://twitter.com/bdorfman)).

FSQSingleLocationSubscriber was originally written and is currently maintained by Brian Dorfman.
