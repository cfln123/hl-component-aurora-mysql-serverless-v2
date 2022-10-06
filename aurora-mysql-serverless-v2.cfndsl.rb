CloudFormation do

  IAM_Role("AuroraMySQLServerlessV2Role") {
    AssumeRolePolicyDocument({
      Version: '2012-10-17',
      Statement: [
          {
          Effect: 'Allow',
          Principal: {
              Service: [
              'lambda.amazonaws.com'
              ]
          },
          Action: 'sts:AssumeRole'
          }
      ]
    })
    Path '/'
    Policies([
      {
          PolicyName: "#{component_name.downcase}-set-logs-retention",
          PolicyDocument: {
          Version: '2012-10-17',
          Statement: [
              {
              Effect: 'Allow',
              Action: [
                  'logs:CreateLogStream',
                  'logs:PutLogEvents'
              ],
              Resource: '*'
              }
          ]
          }
      },
      {
          PolicyName: "#{component_name.downcase}-modify-cluster",
          PolicyDocument: {
          Version: '2012-10-17',
          Statement: [
              {
              Effect: 'Allow',
              Action: [
                  'rds:ModifyDBCluster',
              ],
              Resource: [
                  FnSub("arn:aws:rds:${AWS::Region}:${AWS::AccountId}:cluster:${DBCluster}")
              ]
              },
              {
              Effect: 'Allow',
              Action: [
                  'rds:DescribeDBClusters',
              ],
              Resource: [
                  '*'
              ]
              }
          ]
          }
      }
    ])
  }

  Lambda_Function("AuroraMySQLServerlessV2Lambda") {
    Code({
      ZipFile: <<~CODE
        import sys
        import subprocess
          
        # Upgrade to Boto3 version: 1.21.41
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-I', 'boto3', '--upgrade', '--target', '/tmp', '--no-cache-dir', '--disable-pip-version-check'])
        sys.path.insert(0, '/tmp')
        
        import cfnresponse
        import boto3
        import botocore
        from time import sleep
        
        print(botocore.__version__)
        print(boto3.__version__)
        
        def wait_cluster_status(client, dBClusterIdentifier):
          while True:
            sleep(10)
            
            status = client.describe_db_clusters(DBClusterIdentifier = dBClusterIdentifier)['DBClusters'][0]['Status']
        
            if status == 'available':
              break
        
          print(f"Cluster Status: {status}")
        
        def lambda_handler(event, context):
          print(event)
        
          if (event['RequestType'] == 'Delete'):
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        
          responseData        = {}
          dBClusterIdentifier = event['ResourceProperties']['DBClusterIdentifier']
          minCapacity         = float(event['ResourceProperties']['MinCapacity'])
          maxCapacity         = float(event['ResourceProperties']['MaxCapacity'])
        
          if (event['RequestType'] == 'Create') or (event['RequestType'] == 'Update'):
            try:
              print(f"DBClusterIdentifier: {dBClusterIdentifier}")
              print(f"MinCapacity: {minCapacity}")
              print(f"MaxCapacity: {maxCapacity}")
        
              client = boto3.client('rds')
        
              wait_cluster_status(client, dBClusterIdentifier)
        
              response = client.modify_db_cluster(DBClusterIdentifier=dBClusterIdentifier,
                                                  ServerlessV2ScalingConfiguration={
                                                    'MinCapacity': minCapacity,
                                                    'MaxCapacity': maxCapacity
                                                  })
              
              print(response)
        
              wait_cluster_status(client, dBClusterIdentifier)
        
              responseData['Message'] = 'Success.'
        
              cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
            except Exception as e:
              print(e)
              
              responseData['Message'] = 'Error'
        
              cfnresponse.send(event, context, cfnresponse.FAILED, responseData)
      CODE
    })
    Handler "index.lambda_handler"
    Runtime "python3.9"
    Timeout 300
    Role FnGetAtt("AuroraMySQLServerlessV2Role", :Arn)
  }

  Logs_LogGroup(:AuroraMySQLServerlessV2LogGroup) {
    DependsOn :AuroraMySQLServerlessV2Lambda
    LogGroupName FnSub("/aws/lambda/${AuroraMySQLServerlessV2Lambda}")
    RetentionInDays 30
  }

  Resource("AuroraMySQLServerlessV2CR") {
    DependsOn :AuroraMySQLServerlessV2LogGroup
    Type "Custom::AuroraMySQLServerlessV2"
    Property 'ServiceToken', FnGetAtt("AuroraMySQLServerlessV2Lambda", :Arn)
    Property 'DBClusterIdentifier', Ref(:DBCluster)
    Property 'MinCapacity', Ref(:MinCapacity)
    Property 'MaxCapacity', Ref(:MaxCapacity)
  }

end