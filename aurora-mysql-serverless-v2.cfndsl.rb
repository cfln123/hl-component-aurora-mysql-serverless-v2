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
      ZipFile: File.open("modify.py").read
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