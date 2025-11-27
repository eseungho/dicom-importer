#!/bin/bash
apt-get update && apt-get install -y inotify-tools && apt-get install -y dcmtk
exec "$@"
