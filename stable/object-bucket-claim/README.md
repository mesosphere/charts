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

The following table lists the configurable parameters of the chart and
their default values.

| Parameter                     | Description                                                              | Default |
|:------------------------------|:-------------------------------------------------------------------------|:--------|
| `bucketName`                  | Name of the bucket to create                                             | true    |
| `generateBucketName`          | Prefix of the bucket name with a generated suffix                        | nil     |
| `labels`                      | labels to set on this object                                             | {}      |
| `additionalConfig.maxObjects` | Limit of number of S3 objects this bucket can hold                       | "1000"  |
| `additionalConfig.maxSize`    | Limit of the storage this S3 bucket can use from the S3 storage provider |         |

Specify each parameter using the `--set key=value[,key=value]` argument to
`helm install`.
