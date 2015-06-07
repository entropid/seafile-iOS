
Introduction
============

Seafile-iOS is a the iOS client for [Seafile](http://www.seafile.com).

Build and Run
=============

Follow these steps :

	git clone https://github.com/haiwen/seafile-iOS.git
	cd seafile-iOS
	git submodule init
	git submodule update
	open seafilePro.xcodeproj

Then you can run seafile in xcode simulator.


Improvements
==========

This fork implemented a series of improvements on the original version.

1. Support for iPhone 6 (and iPhone 6 Plus, but some @3x assets are missing)

2. Support for Touch ID authentication

3. Swipe actions for files/folders 

4. Search bar removed (it doesn't work unless you have a license for the Pro version)

5. Popover menu for directory actions

6. More to come…