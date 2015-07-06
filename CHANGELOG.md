## 1.1.2 (2015-07-06)

Features:

 - Add support for background location in iOS9

Bugfixes:

 - Many changes to how region subscribers work to fix issues. Re-connecting regions subscribers to monitored regions from previous app launches should now work as expected.

## 1.1.1 (2015-04-07)

Bugfixes:

 - This fixes a critical bug when building with newer versions of clang (Xcode 6.2+) where the broker would always think that the app was not backgrounded.
 - You must now define the FSQ_IS_APP_EXTENSION when compiling an extension in order to have unavailable apis compiled out.

## 1.1.0 (2015-04-02)

Features:

 - Add support for CLVisit.
 - Add changelog.

Bugfixes:

 - CLLocationManger methods are now correctly always called on main thread.
 - Guard against compiling in uses of UIApplication for extensions.

## 1.0.3 (2014-09-15)

Features:

 - Support for iOS 8.

## 1.0.2 (2014-09-02)

Bugfixes:

 - Add .gitignore and remove files which should have been ignored.
 
## 1.0.1 (2014-08-04)

Bugfixes:

 - Compile out NSAssert and related code if asserts are disabled.

## 1.0.0 (2014-06-03)

Initial release.
