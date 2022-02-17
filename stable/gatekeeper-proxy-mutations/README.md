# Gatekeeper proxy mutation

It is a complementary chart for [Gatekeeper](https://github.com/open-policy-agent/gatekeeper/).

## Introduction

This chart creates proxy mutations for a given configuration.

# Prerequisites

This chart requires gatekeeper chart to be installed.

## Configuration


| Parameter                             | Description                                                          | Default |
|:--------------------------------------|----------------------------------------------------------------------|---------|
| disableMutation                       | Disables mutations - the same parameters is used in gatekeeper chart | false   |
| mutations.podProxySettings.noProxy    | A value of NO\_PROXY variable                                        |         |
| mutations.podProxySettings.httpProxy  | A value of HTTP\_PROXY variable                                      |         |
| mutations.podProxySettings.httpsProxy | A value of HTTPS\_PROXY variable                                     |         |
| mutations.namespaceSelectorForProxy   | Applies mutations on objects whose lables match namespace labels     | {}      |
| mutations.excludeNamespacesFromProxy  | Disables mutations for listed namespaces                             | []      |
