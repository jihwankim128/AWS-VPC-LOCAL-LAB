#!/usr/bin/env bash
set -euo pipefail

dig @192.168.56.6 api.local.test +short
