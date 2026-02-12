import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications'
import * as lambda from 'aws-cdk-lib/aws-lambda'
import * as s3Deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions'
import * as events from 'aws-cdk-lib/aws-events'
import * as eventTarget from 'aws-cdk-lib/aws-events-targets'
import { DockerImageAsset } from 'aws-cdk-lib/aws-ecr-assets';

const fs = require('fs');
const path = require('path');
const awsConfig = require('../awsconfig.json');

const directory = path.resolve();

export class ServerlessOdmStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const vpc = new ec2.Vpc(this, 'VPC', {
      natGateways: 0,
      subnetConfiguration: [
        {
          name: 'Public',
          cidrMask: 24,
          subnetType: ec2.SubnetType.PUBLIC
        }
      ]
    });

    const userData = fs.readFileSync('./userdata.sh').toString();

    const setupCommands = ec2.UserData.forLinux();
    setupCommands.addCommands(userData);

    const multipartUserData = new ec2.MultipartUserData();
    multipartUserData.addPart(ec2.MultipartBody.fromUserData(setupCommands, 'text/x-shellscript; charset="us-ascii"'));

    const launchTemplate = new ec2.LaunchTemplate(this, 'LaunchTemplate', {
      launchTemplateName: 'ServerlessOdmLaunchTemplate',
      userData: multipartUserData,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(50, { 
            volumeType: ec2.EbsDeviceVolumeType.GP3
          })
        }
      ]
    });

    const dockerRole = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'Execution role for the docker container',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ]
    });

    const awsManagedEnvironment = new batch.ManagedEc2EcsComputeEnvironment(this, 'ServerlessOdmCE', {
      vpc,
      minvCpus: awsConfig.computeEnv.minvCpus,
      maxvCpus: awsConfig.computeEnv.maxvCpus,
      instanceTypes: awsConfig.computeEnv.instanceTypes,
      instanceRole: dockerRole,
      launchTemplate: launchTemplate
    });

    const jobQueue = new batch.JobQueue(this, 'ServerlessOdmJobQueue', {
      computeEnvironments: [
        {
          computeEnvironment: awsManagedEnvironment,
          order: 1
        }
      ]
    });

    const dockerImage = new DockerImageAsset(this, 'ServerlessOdmDockerImage', {
      directory: path.join(directory, 'docker'),
    });

    const logging = new ecs.AwsLogDriver({ streamPrefix: "serverlessodmruns" })

    const jobDefinition = new batch.EcsJobDefinition(this, 'ServerlessOdmJobDefinition', {
      timeout: cdk.Duration.hours(24),
      container: new batch.EcsEc2ContainerDefinition(this, 'ServerlessOdmContainerDefinition', {
        command: [
          'sh',
          '-c',
          '/entry.sh',
          'Ref::bucket',
          'Ref::key',
          'output',
        ],
        image: ecs.ContainerImage.fromDockerImageAsset(dockerImage),
        memory: cdk.Size.mebibytes(awsConfig.computeEnv.desiredMemory),
        cpu: awsConfig.computeEnv.desiredCpus, 
        privileged: true,
        volumes: [
            batch.EcsVolume.host({
                name: 'local',
                hostPath: '/mnt/odm_data', 
                containerPath: '/local'
            })
        ],
        logging: logging
      }),
    });

    const dispatchLambdaRole = new iam.Role(this, 'DispatchHandlerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com')
    })

    dispatchLambdaRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"));
    dispatchLambdaRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonS3FullAccess"));
    dispatchLambdaRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName("AWSBatchFullAccess"));

    const snsLambdaRole = new iam.Role(this, 'SnsHandlerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com')
    })

    snsLambdaRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"));
    snsLambdaRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSNSFullAccess"))

    const topic = new sns.Topic(this, 'Topic', {
      displayName: 'Serverless OpenDroneMap'
    })

    topic.addSubscription(new subscriptions.EmailSubscription(awsConfig.notificationEmail))

    const dispatchFunction = new lambda.Function(this, 'DispatchHandler', {
      runtime: lambda.Runtime.NODEJS_LATEST,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('functions/dispatch-handler'),
      role: dispatchLambdaRole,
      environment: {
        JOB_DEFINITION: jobDefinition.jobDefinitionName,
        JOB_QUEUE: jobQueue.jobQueueName
      }
    })

    const snsFunction = new lambda.Function(this, 'SNSHandler', {
      runtime: lambda.Runtime.NODEJS_LATEST,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('functions/sns-handler'),
      role: snsLambdaRole,
      environment: {
        SNS_ARN: topic.topicArn
      }
    })

    const imageryBucket = new s3.Bucket(this, 'Imagery', {      
    });

    imageryBucket.addEventNotification(s3.EventType.OBJECT_CREATED, new s3n.LambdaDestination(dispatchFunction), {suffix: 'dispatch'});
    imageryBucket.grantReadWrite(dockerRole);

    const event = new events.Rule(this, 'NotificationRule', {
      ruleName: 'ServerlessOdmNotificationRule',
      eventPattern: {
        source: ['aws.batch'],
        detailType: ['Batch Job State Change'],
        detail: {
          parameters: {
            bucket: [imageryBucket.bucketName]
          },
          status: ["FAILED","STARTING","SUBMITTED","SUCCEEDED"]
        }
      }
    });

    event.addTarget(new eventTarget.LambdaFunction(snsFunction));

    new s3Deploy.BucketDeployment(this, 'settings yaml', {
      sources: [s3Deploy.Source.asset(directory, { exclude: ['**', '.*', '!settings.yaml'] })],
      destinationBucket: imageryBucket
    });
  }
}
