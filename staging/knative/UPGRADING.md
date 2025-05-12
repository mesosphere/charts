# Upgrading the Knative fork

With the introduction of the Knative Operator, the upgrade process has been simplified. The operator manages the lifecycle of Knative Serving and Eventing components, eliminating the need for manual patching or custom scripts.

## Upgrading

To upgrade Knative, follow these steps:

1. Update the \`Chart.yaml\` dependencies to the desired version of the Knative Operator:
  - Update the \`knative-operator\` dependency version in the \`Chart.yaml\` file.

2. Run the following commands to update the dependencies and upgrade the chart:

```bash
   $ helm dependency update staging/knative
   $ helm upgrade knative-release staging/knative
```

3. Ensure that the \`values.yaml\` file reflects the desired configuration for the new version of Knative Serving and Eventing.

The Knative Operator will handle the deployment and upgrade of the Serving and Eventing components based on the configuration provided in the \`values.yaml\` file.

### Notes

- If there are custom patches or modifications previously applied using the \`./upgrade_knative.sh\` script, ensure that these changes are incorporated into the \`values.yaml\` file or the Helm chart templates.
- The `./upgrade_knative.sh` script is no longer required and can be deprecated.
