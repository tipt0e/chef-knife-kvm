#!/bin/bash

# place this script in each volume pool directory path in which you want to
# use this plugin
# this trickery ensures our template image is the correct one loaded

mv -f /data/vm/$1_r.qcow2 /data/vm/$1.qcow2
virsh vol-delete $1_r.qcow2 --pool vm
