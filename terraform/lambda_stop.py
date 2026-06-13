import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ecs = boto3.client('ecs')
    
    cluster_name = os.environ['CLUSTER_NAME']
    service_name = os.environ['SERVICE_NAME']
    
    logger.info(f"Zatrzymywanie serwisu {service_name} w klastrze {cluster_name}")
    
    try:
        response = ecs.update_service(
            cluster=cluster_name,
            service=service_name,
            desiredCount=0
        )
        
        logger.info(f"Sukces: Serwis {service_name} zatrzymany. DesiredCount: {response['service']['desiredCount']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Serwis {service_name} zatrzymany pomyślnie',
                'cluster': cluster_name,
                'service': service_name
            })
        }
        
    except Exception as e:
        logger.error(f"Błąd: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'cluster': cluster_name,
                'service': service_name
            })
        }
