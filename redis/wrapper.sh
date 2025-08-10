#!/bin/bash

for i in {1..4}; do
  /root/rel-branch/helm-projects/redis/redis-test-sentinel/script/setLabel.sh
  sleep 15
done
