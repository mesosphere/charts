# ObjectBucketClaim Helm Chart

## Chart Details

This chart will do the following:

* Create a ObjectBucketClaim that will be reconciled by your S3-compatible storage provider to create an S3 bucket

## Installing the Chart

To install the chart, use the following:

```console
$ helm install stable/object-bucket-claim
```

## Configuration

The config assumes the fact that it is going to be consumed by dkp platform. But you can change it to also include your own apps.

```yaml
dkp:
  velero:
    enabled: true
    bucketName: dkp-velero
    # generateBucketName: ceph-bkt
    storageClassName: s3-provider-sc

    labels: {}
    additionalConfig:
      # maxObjects: "1000"
      # in string format like "2G", minimum is "4K"
      maxSize: "10G"  
  loki:
    ...
  your-app:
    ...
```

The following table lists the configurable parameters of each app under to top-level `dkp.$app` flag the chart and
their default values. (`$app` is `velero`|`loki`|`your-app` in the example above.)

| Parameter                              | Description                                                              | Default |
|:---------------------------------------|:-------------------------------------------------------------------------|:--------|
| `dkp.$app.bucketName`                  | Name of the bucket to create                                             | true    |
| `dkp.$app.generateBucketName`          | Prefix of the bucket name with a generated suffix                        | nil     |
| `dkp.$app.labels`                      | labels to set on this object                                             | {}      |
| `dkp.$app.additionalConfig.maxObjects` | Limit of number of S3 objects this bucket can hold                       | ""      |
| `dkp.$app.additionalConfig.maxSize`    | Limit of the storage this S3 bucket can use from the S3 storage provider | ""      |

Specify each parameter using the `--set key=value[,key=value]` argument to
`helm install`.
