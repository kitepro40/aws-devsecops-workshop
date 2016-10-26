#!/usr/bin/env ruby

require 'cfndsl'

CloudFormation do
  Description 'AWS DevSecOps Workshop Environment + Jenkins (VPC+EC2 Instance)'

  Parameter(:InstanceType) do
    Description 'EC2 Instance Type to deploy.'
    Type 'String'
    Default 't2.micro'
  end

  Parameter(:WorldCIDR) do
    Description 'The CIDR block to allow HTTP access to Jenkins with.'
    Type 'String'
    Default '0.0.0.0/0'
  end

  Parameter(:GithubCIDR) do
    Description 'The CIDR block to allow HTTP access to Jenkins with.'
    Type 'String'
    # https://help.github.com/articles/what-ip-addresses-does-github-use-that-i-should-whitelist/
    Default '192.30.252.0/22'
  end

  EC2_VPC(:VPC) do
    CidrBlock '11.0.0.0/16'
    EnableDnsSupport 'true'
    EnableDnsHostnames 'true'
    Tags [
      {
        Key: 'Name',
        Value: Ref('AWS::StackName')
      }
    ]
  end

  EC2_Subnet(:Subnet) do
    VpcId Ref(:VPC)
    CidrBlock '11.0.0.0/20'
    MapPublicIpOnLaunch true
    Tags [
      {
        Key: 'Name',
        Value: Ref('AWS::StackName')
      }
    ]
  end

  EC2_InternetGateway(:InternetGateway) do
    Tags [
      {
        Key: 'Name',
        Value: Ref('AWS::StackName')
      }
    ]
  end

  EC2_VPCGatewayAttachment(:AttachGateway) do
    VpcId Ref(:VPC)
    InternetGatewayId Ref(:InternetGateway)
  end

  EC2_RouteTable(:RouteTable) do
    VpcId Ref(:VPC)
    Tags [
      {
        Key: 'Name',
        Value: Ref('AWS::StackName')
      }
    ]
  end

  EC2_Route(:Route) do
    DependsOn :AttachGateway
    RouteTableId Ref(:RouteTable)
    DestinationCidrBlock Ref(:WorldCIDR)
    GatewayId Ref(:InternetGateway)
  end

  EC2_SubnetRouteTableAssociation(:SubnetAssociation) do
    SubnetId Ref(:Subnet)
    RouteTableId Ref(:RouteTable)
  end

  EC2_SecurityGroup(:SecurityGroup) do
    VpcId Ref(:VPC)
    GroupDescription 'HTTP access for deployment.'
    SecurityGroupIngress [
      {
        # Jenkins HTTP
        IpProtocol: 'tcp',
        FromPort: '8080',
        ToPort: '8080',
        CidrIp: Ref(:WorldCIDR)
      },
      {
        # DEBUGGING SSH
        IpProtocol: 'tcp',
        FromPort: '22',
        ToPort: '22',
        CidrIp: Ref(:WorldCIDR)
      }
    ]
    SecurityGroupEgress [
      {
        # Jenkins HTTP
        IpProtocol: 'tcp',
        FromPort: '8080',
        ToPort: '8080',
        CidrIp: Ref(:WorldCIDR)
      },
      {
        # Github
        IpProtocol: 'tcp',
        FromPort: '22',
        ToPort: '22',
        CidrIp: Ref(:GithubCIDR)
      },
      {
        # Github
        IpProtocol: 'tcp',
        FromPort: '9418',
        ToPort: '9418',
        CidrIp: Ref(:GithubCIDR)
      },
      {
        # World HTTP
        IpProtocol: 'tcp',
        FromPort: '80',
        ToPort: '80',
        CidrIp: Ref(:WorldCIDR)
      },
      {
        # World HTTPS
        IpProtocol: 'tcp',
        FromPort: '443',
        ToPort: '443',
        CidrIp: Ref(:WorldCIDR)
      }
    ]
  end

  CloudFormation_WaitConditionHandle(:WaitHandle)

  CloudFormation_WaitCondition(:EC2Waiter) do
    DependsOn :JenkinsServer
    Handle Ref(:WaitHandle)
    Timeout '600'
  end

  EC2_Instance(:JenkinsServer) do
    DependsOn :AttachGateway
    ImageId 'ami-32114e25'
    InstanceType Ref(:InstanceType)
    IamInstanceProfile Ref(:JenkinsInstanceProfile)
    KeyName 'rmurphy-goldbase'
    NetworkInterfaces [
      {
        AssociatePublicIpAddress: true,
        DeleteOnTermination: true,
        SubnetId: Ref(:Subnet),
        DeviceIndex: 0,
        GroupSet: [Ref(:SecurityGroup)]
      }
    ]
    Tags [
      {
        Key: 'Name',
        Value: FnJoin(' - ', [
                        'AWS DevSecOps Workshop Jenkins',
                        ENV['USER'].upcase
                      ])
      }
    ]

    wait_handle = [
      "#!/bin/bash\n",
      'export wait_handle="', Ref(:WaitHandle), "\"\n",
      'export vpc_id="', Ref(:VPC), "\"\n",
      'export subnet_id="', Ref(:Subnet), "\"\n",
      'export world_cidr="', Ref(:WorldCIDR), "\"\n"
    ]

    script_path = 'provisioning/cloudformation/jenkins-userdata.sh'
    script_data = File.read(script_path).split("\n").map { |line| line + "\n" }

    UserData FnBase64(FnJoin('', wait_handle + script_data))
  end

  IAM_Role(:JenkinsRole) do
    AssumeRolePolicyDocument(
      Statement: [{
        Effect: 'Allow',
        Principal: {
          Service: [
            'ec2.amazonaws.com'
          ]
        },
        Action: [
          'sts:AssumeRole'
        ]
      }]
    )

    Path '/'

    Policies [{
      PolicyName: 'aws-devsecops-jenkins-role',
      PolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Action: 'cloudformation:*',
            Resource: '*'
          },
          {
            Effect: 'Allow',
            Action: 'ec2:*',
            Resource: '*'
          }
        ]
      }
    }]
  end

  IAM_InstanceProfile(:JenkinsInstanceProfile) do
    Path '/'
    Roles [Ref(:JenkinsRole)]
  end

  Output(:JenkinsIP, FnGetAtt(:JenkinsServer, 'PublicIp'))
end
