#!/usr/bin/env bash
#set -o xtrace

kapp deploy -a helm-supply-chain \
  -f <(ytt -f supply-chain.yaml -f templates --data-values-file templates/supply-chain-values.yaml)

