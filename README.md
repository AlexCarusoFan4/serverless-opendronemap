# Serverless OpenDroneMap - Imagery Processing Made Easy with AWS

Serverless OpenDroneMap makes running OpenDroneMap (https://github.com/OpenDroneMap/ODM) as simple as uploading your images and downloading the results. Serverless OpenDroneMap is a set of automated tooling built on top of AWS Batch that monitors
an S3 bucket for changes, and when it detects the presence of a trigger file, it will launch a
batch job to process your images.

Serverless OpenDroneMap borrows inspiration and some code from https://github.com/hobuinc/codm, but makes different
choices about dependencies. In particular, everything is handled by the CDK so it can be built and deployed
with one single command.

This is an adaptation of the original DroneYard to account for deprecated AWS features and updated dependencies  - including code originally from https://github.com/TotallyGatsby/DroneYard. A huge thank you to @TotallyGatsby for their DroneYard solution.

The goal is to make setup and deployment as simple as possible, and rely only on AWS, Docker, and NPM.

<img width="3363" height="2283" alt="Serverless OpenDroneMap architecture diagram" src="https://github.com/user-attachments/assets/5286a374-fe46-4e00-808a-612c2e2bd1cd" />

## Usage

### Prerequisites
Serverless OpenDroneMap depends on AWS, AWS CDK, NPM, and Docker.

You will need to install the following in your development environment:

- Git (https://github.com/git-guides/install-git)
- Node/Node Package Manager (https://nodejs.org/en/download/)
- Docker Desktop (https://docs.docker.com/desktop/)
- AWS CLI (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- AWS CDK (https://docs.aws.amazon.com/cdk/v2/guide/getting-started.html)

### Configuration
Configure the AWS CLI client with credentials and details for your deployment AWS Account (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

Make sure you are using an account or role with adequate permissions to deploy all of the resources.

The stack can be configured in `awsconfig.json`, which is where you'll set instance types, the target CPU and memory requirements and an email address to subscribe to batch job notifications.

Please note that you will need to use an instance type that has a "d" suffix (indicating "Disk").

The disk will need to have enough space to hold your imagery dataset and any temporary files generating during the OpenDroneMap processing run.

The default r6id.2xlarge should be suitable for most jobs at a good price point.

Prior to deployment, make sure Docker is running (required to build the docker container image).

### Deployment
```
git clone https://github.com/AlexCarusoFan4/serverless-opendronemap.git
```
```
cd serverless-opendronemap
```
```
npm install
```
If this is your first time deploying to this account, you will need to bootstrap your AWS account.
```
cdk bootstrap
```
Otherwise, simply:
```
cdk deploy --require-approval never
```

Everything is handled by AWS CDK. It will deploy all the resources for you automatically.

### Usage
After the solution is deployed, you will have an S3 bucket, eg:

serverlessodmstack-imageryfeb8bc81-a8jnkxd7mvmo

Create a new folder in that bucket for your project and upload your imagery dataset. The AWS CLI and `s3 sync` is useful for
this, but any client will work.

Make sure your folder name doesn't contain any spaces or problematic characters.

You can also optionally upload a settings.yaml file where you set the parameters (https://docs.opendronemap.org/arguments/) for the ODM processing job.

Some pre-set options have been provided in the repository here: [serverless-opendronemap/assets/settings](/assets/settings).

If you do not provide one, it will use the provided one in the top level of the S3 bucket by default.

There is support for providing a ground control point (GCP) file (https://docs.opendronemap.org/gcp/) and custom boundary (https://docs.opendronemap.org/arguments/boundary/).

The files must be named gcp-list.txt and boundary.json respectively.

Once all of your images have been uploaded, create and upload a new, empty file named `dispatch` (no file type extension) to the folder. An example has been provided in the repository here: [serverless-opendronemap/assets/dispatch](/assets/dispatch).

This will start the workflow. When the image processing is complete, a folder called `output` will
be present alongside your photos.

Download your outputs to view them with software and use them in your projects.

If you need some inspiration, example datasets can be found here: https://opendronemap.org/odm/datasets/.

### Removal
```
cdk destroy
```

This will retain your S3 bucket. To avoid
charges for S3 you'll want to manually remove anything you uploaded (empty bucket, then delete bucket).
