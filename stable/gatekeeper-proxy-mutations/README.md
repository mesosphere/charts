# Gatekeeper proxy mutation

It is a complementary chart for [Gatekeeper](https://github.com/open-policy-agent/gatekeeper/).

## Introduction

This chart creates proxy mutations for a given configuration.

# Prerequisites

This chart requires gatekeeper chart to be installed.

## Configuration


| Parameter                                        | Description                                                                                                                                                                                                                                                                                                                                                                                                                            | Default                                  |
|:-------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------|
| disableMutation                                  | Disables mutations - the same parameter is used in gatekeeper chart. When `true`, no `Assign` resources are rendered.                                                                                                                                                                                                                                                                                                                  | false                                    |
| mutations.podProxySettings.noProxy               | Value of `NO_PROXY` environment variable.                                                                                                                                                                                                                                                                                                                                                                                              |                                          |
| mutations.podProxySettings.httpProxy             | Value of `HTTP_PROXY` environment variable.                                                                                                                                                                                                                                                                                                                                                                                            |                                          |
| mutations.podProxySettings.httpsProxy            | Value of `HTTPS_PROXY` environment variable.                                                                                                                                                                                                                                                                                                                                                                                           |                                          |
| mutations.namespaceSelectorForProxy              | Applies proxy mutations on objects whose namespace labels match.                                                                                                                                                                                                                                                                                                                                                                       | {}                                       |
| mutations.excludeNamespacesFromProxy             | Disables proxy mutations for listed namespaces.                                                                                                                                                                                                                                                                                                                                                                                        | []                                       |
