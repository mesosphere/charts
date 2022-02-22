# Cert-manager CRDs

This chart provides cert-manager CRDs.

## Introduction

This chart is meant to be used along upstream `cert-manager` chart. The reason to do it in that way is that chart bundles CRDs that are not included in the `crds` directory in the upstream chart which prevents Flux to manage those properly. Moreover, the goal is to keep CRDs once the `cert-manager` app (as kommander app) is removed from attached clusters so the remaining apps can stay operational (they required `cert-manager` CRDs).

## Upgrading the chart

There is a makefile target `update`. It pulls CRDs from the `cert-manager` github repository and updates `appVersion` attribute in `Charts.yaml`. Once executed, the changes can be added and commited to `mesosphere/charts` repository.
