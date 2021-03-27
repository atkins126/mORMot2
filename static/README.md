# mORMot Framework Static Files

## Folder Content

This folder should contain all raw binary files needed for FPC and Delphi static linking.

If this folder is void (e.g. when retrieved from https://synopse.info/fossil), you can download all the needed sub-folders from a matching release from https://github.com/synopse/mORMot2/releases

## Static Linking

Those .o/.obj files were compiled from optimized C/asm, for the best performance, and reduce dependencies or version problems.

Note that such external files are not mandatory to compile the framework source code. There is always a "pure pascal" fallback code available, or use e.g. the official external sqlite3 library.

## Delphi Setup

The framework source code uses relative paths to include the expected .o/.obj files from the static\delphi sub-folder, so nothing special is needed.


## FPC Cross-Platform Setup

Ensure that "Libraries -fFl" in your FPC project options is defined as:

      ..\static\$(TargetCPU)-$(TargetOS)

(replace ..\static by an absolute/relative path to this folder)

It will ensure that when (cross-)compiling your project, FPC will link the expected .o binary files, depending on the target system.

## Keep In Synch

Ensure you keep in synch these binaries with the main framework source code.
Otherwise, some random/unexpected errors may occur.

## Compile From Source

Take a look at [the res/static folder](../res/static) for the reference C source code used to generate those static files. 