import json
import boto3
import os

def lambda_handler(event, context):
    ecs = boto3.client('ecs')
    
    cluster_name = os.environ['CLUSTER_NAME']
    service_name = os.environ['SERVICE_NAME']
    
    print(f"Zatrzymywanie serwisu {service_name} w klastrze {cluster_name}")
    
    try:
        response = ecs.update_service(
            cluster=cluster_name,
            service=service_name,
            desired_count=0
        )
        
        print(f"Sukces: Serwis {service_name} zatrzymany")
        print(f"Desired count: {response['service']['desiredCount']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Serwis {service_name} zatrzymany pomyślnie',
                'cluster': cluster_name,
                'service': service_name
            })
        }
        
    except Exception as e:
        print(f"Błąd: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'cluster': cluster_name,
                'service': service_name
            })
        }
