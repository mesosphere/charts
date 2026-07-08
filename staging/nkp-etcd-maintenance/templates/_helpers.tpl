{{/*
Expand the chart name and version into a single label value.
Usage: {{ include "nkp-etcd-maintenance.chart" . }}

Why this exists: every resource the chart creates carries a
`helm.sh/chart=<name>-<version>` label so operators can identify which
chart release created which object (useful for cleanup, audit, and
"who owns this CronJob?" questions). Hard-coding the value in every
template would mean N places to update on every version bump; this
helper lets us compute it once.

Implementation notes (left-to-right in the pipeline below):
  * `printf "%s-%s" .Chart.Name .Chart.Version`
        → "nkp-etcd-maintenance-0.3.0"
  * `replace "+" "_"`
        → SemVer build-metadata like "1.0.0+abc" is illegal in a
          Kubernetes label value; substitute "+" with "_".
  * `trunc 63`
        → Kubernetes label values cap at 63 characters; longer values
          are silently rejected by the API server. Truncating here
          guarantees we never produce an invalid label.
  * `trimSuffix "-"`
        → if `trunc 63` cut us off mid-version with a trailing "-",
          strip it so we never emit "...-0.3.0-".
*/}}
{{- define "nkp-etcd-maintenance.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
