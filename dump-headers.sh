#!/usr/bin/env bash

class-dump \
    /System/Library/PrivateFrameworks/TCC.framework/Versions/A/Resources/tccd \
    -H -o headers/ -s -S
sed -r -e '/^\-\s+\(void\)\.cxx_destruct;$/d' -e 's:;\s+// @synthesize.*:;:g' \
    -i headers/*.h
clang-format -i headers/*.h
