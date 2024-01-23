#!/usr/bin/env bash
#set -o xtrace

kapp deploy -a helm-supply-chain \
  -f <(ytt -f config/supply-chain.yaml -f templates --data-values-file config/templates/supply-chain-values.yaml)

