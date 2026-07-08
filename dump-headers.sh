#!/usr/bin/env bash

class-dump \
    /System/Library/PrivateFrameworks/TCC.framework/Versions/A/Resources/tccd \
    -H -o headers/ -s -S
sed -r -e '/^\-\s+\(void\)\.cxx_destruct;$/d' -e 's:;\s+// @synthesize.*:;:g' \
    -i headers/*.h
clang-format -i headers/*.h
# Drop class-dump noise carrying no TCC-specific information: empty interfaces
# (libTCCD, TCCDDatabase) and the verbatim system NSObject protocol.
rm -f headers/libTCCD.h headers/TCCDDatabase.h headers/NSObject-Protocol.h
