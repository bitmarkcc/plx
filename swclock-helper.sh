#!/bin/bash

set -e

while true
do
	sleep 60
	touch /var/lib/misc/openrc-shutdowntime
done
