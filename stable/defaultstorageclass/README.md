# defaultstorageclass

Webhooks and controllers relating to default storage classes. Currently, it only contains a validation webhook that returns an error if there is > 1 default storage class resulting from the operation. The source repo is at https://github.com/mesosphere/defaultstorageclass.

Run `update.sh <defaultstorageclass_tag>` to update the chart and do a sanity check by running `test.sh <defaultstorageclass_tag>`.
