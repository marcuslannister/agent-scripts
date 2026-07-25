#!/usr/bin/env bash

TOPOLOGY_ERROR_CODE=1
TOPOLOGY_ERROR_MESSAGE=

topology_fail() { # exit_code message
  TOPOLOGY_ERROR_CODE="$1"
  TOPOLOGY_ERROR_MESSAGE="$2"
  return "$1"
}
