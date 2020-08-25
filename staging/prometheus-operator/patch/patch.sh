#!/bin/bash

for p in patch/patch_*.sh; do
    BASEDIR=${BASEDIR} $p
done
