Created by brodriguez255 on 12/19/2018

Tried to user Composer to create a package for macOS 10.14.2. Created the package successfully, but was not able to install from the package.

The suggested command for cli was a great start, but I made a few modifications that helped me out a lot.

Step 1: Change Permissions

Once you've got the installer sitting in /Applications, change the permissions to the app.

chmod -R 755 Install macOS Mojave.app

Step 2: Build the Package and Preserve Permissions

Running this will build the package and preserve the permissions that you applied with the chmod.

pkgbuild --install-location /Applications/ --component "/Applications/Install macOS Mojave.app" --ownership preserve "/Applications/PACKAGE_NAME.pkg"
