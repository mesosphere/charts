# Upgrading the Knative fork

There are no upstream Helm charts for Knative. Instead, we pull in the required YAML files ([Serving with HPA](https://knative.dev/docs/install/yaml-install/serving/install-serving-with-yaml/) and [Eventing](https://knative.dev/docs/install/yaml-install/eventing/install-eventing-with-yaml/)) and apply patches to them, and add them to our own Charts.

## Upgrading

To upgrade Knative, first check to see if the version tags are correct, then run:
```sh
./upgrade_knative.sh
```

The upgrade script:
- Pulls in the yaml files for the latest version of Knative Serving and Eventing
- Applies the following patches to the yaml files:
  - Relax PodDisruptionBudget
  - Several miscellaneous linter related fixes
  - Replaces sha256 tags with standard image tags for airgapped environments
- Cleans up and commits the changes
- Reminds you to go in and manually bump the version in the Chart.yaml files for the base chart and two subcharts
