# What is this?
This is my custom CLI menu thing for ReVanced CLI. It allows you to download the latest CLI JAR and Patches RVP files from GitHub (revanced patches repo is currently down, use a local file if you have one) and choose patches from a list. It's more convenient than using the CLI directly, but yeah..

# How to use?
For Windows, you need Git Bash (https://git-scm.com/downloads or https://gitforwindows.org/) to run the shell script. For Linux, you can run the shell script in your terminal. Just make sure you have Java installed (https://adoptium.net/temurin/releases) as well as `jq` (https://jqlang.org/download/). You need `jq` whether you're using Windows or Linux.

Windows in Git Bash: Use `./menu-windows.sh`  
Linux: Use `./menu.sh`

# keystore file
Use the same `.keystore` file for all your patched apps so you won't have to keep reinstalling when you change the patched APK filename. Put your `.keystore` file in a `output/` directory in the same folder as the shell script. This `output/` directory will be where the final patched APK will be placed to as well.

So basically, patch your first app, the script makes a new one under the same name (if it doesn't already exist), then just use that same keystore file for your other apps. Set it in the menu with option `D`. Type in the name of the keystore without the `.keystore` extension. For example, if your keystore file is named `patched_app.keystore`, just type in `patched_app` in the menu.

### Note
Your options aren't stored after closing the script. I apologize :\(...

<hr>

Copyright (c) Diego Perez (iKarTehFox)

Licensed under Mozilla Public License 2.0 (MPL-2.0)