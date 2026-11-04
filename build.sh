#!/bin/bash

./scripts/setup.sh
source scripts/envsetup.sh
lunch qemu_debug
./scripts/build_all.sh
./scripts/gen_compile_commands.sh