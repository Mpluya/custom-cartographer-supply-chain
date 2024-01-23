# Custom Source Scan Sign to Helm Supply Chain

This guide will walk you through how to install a custom supply chain that will pull source code, build an image from a Dockerfile using Kaniko, sign the image and then perform a Helm package and push using a Tekton Task.

This supplychain has been tested using this sample golang application. The source code and TAP GUI can be found here:

* [TAP GUI Supply Chain](https://tap-gui.view.cssa.tapsme.org/supply-chain/build/mae/app-golang-kaniko)
* [Sample Golang Source Code](https://github.com/Mpluya/app-golang-kaniko)

Make sure you have the ytt and kapp cli's installed as well:

* [Install ytt cli](https://carvel.dev/ytt/docs/v0.46.x/install/)
* [Install kapp cli](https://carvel.dev/kapp/docs/v0.59.x/install/)

## Installation

We will use [Kapp](https://carvel.dev/kapp/) to install the supply chain onto the cluster. We first need to setup a few things:

### supply-chain-values.yaml

Adjust these fields to match the installation of tap. Mainly these fields:

```
registry:
  server: cxscssa.azurecr.io
  repository: tap-build/workloads

gitops:
  ssh_secret: tenant-gitops-ssh
  server_address: ssh://git@github.com
  repository_owner: Mpluya
  repository_name: tap-azure-workload-config-repo
```

### Update the Supply Chain Templates

Read the Individual Component section to make appropriate adjustments before installation. 

### Install Supply Chain

Run the install.sh shell script to use kapp to install the supply chain.

Re-run this script if you make changes and want them applied.

### Delete Supply Chain

Run the delete.sh shell script to delete the kapp app that installs the supply chain. 

### Trivy Scanner Setup

You will need to install the Trivy scanner in your developer namespace. You can find the instructions here:

* [Install Trivy Scanner](https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.7/tap/scst-scan-install-trivy-integration.html)

## Submitting a Workload

In order for a workload to be picked up by the new supply chain the following label needs to be set: 

* `apps.tanzu.vmware.com/workload-type: helm` - The workload type label needs to be set to helm.

If you want to add additional tags to the workload that can be by using the following parameter:

* `docker_build_extra_args` - This allows you to set additional tags onto the build image. You need to follow the format of adding two values with the `--destination` flag and it's  value.

The rest of the fields can stay as described in the TAP Documentation. Adjustments will need to be made to the name, namespace, source sections as needed.

### Example Workload

```
apiVersion: carto.run/v1alpha1
kind: Workload
metadata:
  labels:
    app.kubernetes.io/part-of: app-golang-kaniko
    apps.tanzu.vmware.com/workload-type: helm
  name: app-golang-kaniko
  namespace: mae
spec:
  params:
  - name: dockerfile
    value: ./Dockerfile
  - name: docker_build_extra_args
    value:
    - --destination
    - cxscssa.azurecr.io/tap-build/workloads/app-golang-kaniko-mae:0.0.1
  source:
    git:
      ref:
        branch: main
      url: https://github.com/Mpluya/app-golang-kaniko
```

## Individual Components

### supply-chain.yaml

The `supply-chain.yaml` contains 4 steps:

* `source-provider` - This will stamp out a Flux GitRepository resource to pull the source code that is configured in the Workload yaml.
* `image-provider` -  This will stamp out a Tekton TaskRun that will use a Tekton Task to use kaniko to build the image, sign the image, and push the image and signature to the configured Image Registry.
* `image-scanner` - This will stamp out an ImageVulnerabilityScan resource (Custom TAP CRD). This will run the image through the configure Trivy scanner and publish the results to the Metadata store.
* `write-helm` - This will stamp out a Tekton TaskRun that will use a Tekton Task to package the helm chart and publish it a location. 

The `supply-chain-values.yaml` should contain the values you want to set on the supply chain. Ytt will be used to inject the values into the supply chain.

### source-template.yaml

This ClusterConfigTemplate is used by the `source-provider` step and does not need to be modified. It will use Flux to stamp out either a GitRepository, MavenRepository, or ImageRepository resource to pull source code, etc.

* https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.7/tap/scc-ootb-template-reference.html#sourcetemplate-0 

### kaniko-template.yaml

This ClusterConfigTemplate is used by the `image-provider` step to initiate the kaniko build. No modifications are needed.

* https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.7/tap/scc-ootb-template-reference.html#kanikotemplate-28 

### kaniko-build-and-sign.yml

This Tekton Task is used by the `image-provider` step to build the image using kaniko, but to also sign and verify the image using cosign. 

**Note:** The sign and verify steps need to be changed to use the correct cosign key. The verify step can be removed. The `bitnami/cosign:2.2.2` may also be replaced with your choice of image.

```
- name: sign
  image: bitnami/cosign:2.2.2
  script: |
    cosign sign --key k8s://mae/cosign "$(params.image)@$(cat $(results.image_digest.path))" --tlog-upload=false
  securityContext:
    runAsUser: 0
- name: verify
  image: bitnami/cosign:2.2.2
  script: |
    cosign verify --key k8s://mae/cosign "$(params.image)@$(cat $(results.image_digest.path))" --insecure-ignore-tlog=true
  securityContext:
    runAsUser: 0
```

### image-vulnerability-scan-trivy.yaml

This ClusterConfigTemplate is used in the `image-scanner` step of the supply chain. This uses the out of the box scanner Trivy. 

This step will eventually need to be swapped out for a custom scanner. For example, BlackDuck. 

No changes are needed in this template, but the Trivy scanner needs to be installed for it to work properly. 

### helm-writer.yaml

This ClusterTemplate is used by the `write-helm` step of the supply chain. It will stamp out a TaskRun that will package and publish helm. 

No charges are needed in this template.

### helm-writer-tekton-task.yaml

This Tekton Task has multiple steps. 

* `tools` - It first pulls tools and installed them onto an empty volume for /tools. **NOTE:** This step can replaced with a custom image that contains the helm, yq, etc. tools needed.
* `pull-source-code` - It pulls the source code downloaded from flux and places it on an empty volume mount for /source.
* `helm-package` - This steps runs a `helm package` against the pulled source code.
* `helm-publish` - This steps runs a `helm push` on the packaged helm charts.

#### Notes: 

These steps will need customizations:

* You can most likely replace the tools step entirely if you have an image with all the necessary cli's and tools. This can be referenced in the the other 3 steps to replace the tap-packages image. 
* The bash scripting makes assumptions on the location of the helm directories. This will need to be parameterized if those locations are differnt. 

You can find out more about Tekton Tasks in their [official documentation.](https://tekton.dev/docs/pipelines/tasks/)
