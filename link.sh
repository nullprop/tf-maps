#!/bin/bash

TF="$HOME/.steam/steam/steamapps/common/Team Fortress 2/tf"

mkdir -pv "$TF/scripts/vscripts/"
ln -s "$(pwd)/scripts/vscripts/jump_wallrun" "$TF/scripts/vscripts/jump_wallrun"
