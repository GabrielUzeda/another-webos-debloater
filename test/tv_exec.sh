#!/bin/sh
TV_IP="10.1.1.11"
(
  cat
  echo ""
  echo "exit"
) | nc -w 120 "$TV_IP" 23
