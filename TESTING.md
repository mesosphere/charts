# Testing

## Testing against Konvoy

Testing chart changes against Konvoy requires the following:

  1. hosting your own chart
  1. updating the addon repo (e.g. `kubernetes-base-addons`, `kubeaddons-kommander`)
  1. updating the addon in Konvoy's `cluster.yaml`

### Testing flow

Assuming you've forked the `mesosphere/charts` repo, the following is a guide
on how to manually test your changes from the point of running `konvoy up`.

#### Packaging your chart

  1. Make chart changes
  1. Update `Chart.yaml`
      - Update `home` to point to your fork
      - Increment `version` based on your chart's versioning scheme; commonly [semver](https://semver.org/#semantic-versioning-specification-semver).
  1. Check your chart has acceptable values/yaml: `helm lint .`
  1. Package your chart: `helm package .`

#### Hosting your chart

In Github, you can host charts from your own repository.
 See [Configuring a publishing source for your Github
 Pages](https://help.github.com/en/github/working-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
 A commonly used branch is `gh-pages`.

  1. Generate the `index.yaml` file for your chart. If you're updating a
    `stable` chart:

      ```sh
      helm repo index --url "https://<your_github_org>.github.io/charts/stable" .
      ```

  1. Copy the new chart details under the `entries:` section.
   This is used later to add a new entry to the remote `index.yaml` file.
  1. Switch to the `gh-pages` branch: `git checkout gh-pages`
  1. Copy your local helm archive to the appropriate directory: `cp <chart_tgz> ../stable`
  1. Update the `index.yaml` file inside of that same directory to include your
    new chart details: `vim ../stable/index.yaml`
      - Here you add a new entry for the chart version you're testing
  1. Commit and push your changes to the `gh-pages` branch
  1. Now your chart is hosted at `https://<your_github_org>.github.io/charts/stable/<chart.tgz>`

#### Updating the addon repo

Next, you'll need to update the addon that references the chart. Depending on
 your permissions, you may have to fork the addons repo. For example, if you're
 updating the `dashboard` chart in `kubernetes-base-addons`, you'll need to
 update the `<repo>/kubernetes-base-addons/addons/dashboard/<version>/dashboard-<x>.yaml`
 file.

  1. Update the `chartReference` section:
      - Point `repo` to your hosted chart url
      - Update `version` to the chart you're testing
  1. Commit and push changes to a branch. This branch will be referenced in
   Konvoy's `cluster.yaml`

#### Deploying addon changes in Konvoy

To deploy Konvoy using your latest addon changes, update Konvoy's
 `cluster.yaml` `addons:` section:

  1. Update `configRepository` to point to your addons repository
  1. Update `configVersion` to the your testing branch
  1. Run `konvoy up`
      - If you already have a running Konvoy cluster, run `konvoy deploy addons`

Your chart changes should now be reflected in the Addon deployment
