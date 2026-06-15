import json
import boto3
import os
import logging
from botocore.exceptions import ClientError
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

def put_stop_failure_metric(cluster_name, service_name, region):
    """
    Wysyła metrykę do CloudWatch która uruchomi alarm w AWS Console
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='Bastion/AutoStop',
            MetricData=[
                {
                    'MetricName': 'StopFailure',
                    'Dimensions': [
                        {
                            'Name': 'ClusterName',
                            'Value': cluster_name
                        },
                        {
                            'Name': 'ServiceName',
                            'Value': service_name
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        logger.info("✅ Metryka błędu wysłana do CloudWatch - alarm pojawi się w konsoli")
    except Exception as e:
        logger.error(f"Błąd wysyłki metryki: {str(e)}")

def verify_service_stopped(cluster_name, service_name, max_wait_seconds=120):
    """
    Weryfikuje czy serwis rzeczywiście się zatrzymał
    """
    import time
    start_time = datetime.utcnow()
    final_running_count = None
    
    while (datetime.utcnow() - start_time).total_seconds() < max_wait_seconds:
        try:
            response = ecs.describe_services(
                cluster=cluster_name,
                services=[service_name]
            )
            
            if not response['services']:
                logger.info("Serwis nie istnieje - uznajemy za zatrzymany")
                return True, 0
            
            service = response['services'][0]
            running_count = service['runningCount']
            final_running_count = running_count
            
            if running_count == 0:
                logger.info(f"Serwis zatrzymany: runningCount=0")
                return True, 0
            
            logger.info(f"Czekanie na zatrzymanie... runningCount={running_count}")
            time.sleep(10)
            
        except ClientError as e:
            if e.response['Error']['Code'] in ['ServiceNotFound', 'ServiceNotActive']:
                return True, 0
            raise
    
    logger.warning(f"Timeout: serwis nie zatrzymał się po {max_wait_seconds}s (runningCount={final_running_count})")
    return False, final_running_count if final_running_count is not None else 0

def lambda_handler(event, context):
    cluster_name = os.environ['CLUSTER_NAME']
    service_name = os.environ['SERVICE_NAME']
    region = os.environ['AWS_REGION']
    
    logger.info(f"=== AUTO-STOP START ===")
    logger.info(f"Cluster: {cluster_name}")
    logger.info(f"Service: {service_name}")
    logger.info(f"Region: {region}")
    
    try:
        # Krok 1: Sprawdź aktualny stan
        logger.info("Sprawdzanie stanu serwisu...")
        describe_response = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        
        if not describe_response['services']:
            logger.info("Serwis nie istnieje - kończę")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Serwis nie istnieje',
                    'cluster': cluster_name,
                    'service': service_name
                })
            }
        
        current_service = describe_response['services'][0]
        current_running = current_service['runningCount']
        
        if current_running == 0:
            logger.info("Serwis już zatrzymany (runningCount=0)")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Serwis już zatrzymany',
                    'cluster': cluster_name,
                    'service': service_name
                })
            }
        
        logger.info(f"Aktualny stan: runningCount={current_running}")
        
        # Krok 2: Zatrzymaj serwis
        logger.info(f"Wysyłanie update-service (desiredCount=0)...")
        update_response = ecs.update_service(
            cluster=cluster_name,
            service=service_name,
            desiredCount=0
        )
        
        logger.info(f"Sukces: update_service wysłane")
        
        # Krok 3: Weryfikacja czy zatrzymał się
        logger.info("Weryfikacja zatrzymania...")
        stopped, final_running_count = verify_service_stopped(cluster_name, service_name)
        
        if stopped:
            logger.info("✅ AUTO-STOP SUCCESS")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Serwis {service_name} zatrzymany pomyślnie',
                    'cluster': cluster_name,
                    'service': service_name,
                    'verified': True
                })
            }
        else:
            # Krok 4: Circuit breaker - serwis nie zatrzymał się
            error_msg = f"Serwis nie zatrzymał się po 120s (runningCount={final_running_count})"
            logger.error(f"❌ {error_msg}")
            
            # 🔔 Wysyła metrykę która uruchomi ALARM w AWS Console
            put_stop_failure_metric(cluster_name, service_name, region)
            
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': error_msg,
                    'cluster': cluster_name,
                    'service': service_name,
                    'console_alarm_triggered': True
                })
            }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = f"{error_code}: {e.response['Error']['Message']}"
        
        logger.error(f"❌ AWS API Error: {error_message}")
        
        # Circuit breaker dla specyficznych błędów
        if error_code in ['ServiceNotFound', 'ServiceNotActive', 'ClusterNotFound']:
            logger.warning(f"Serwis/Klaster nie istnieje - uznajemy za zatrzymany")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Serwis/Klaster nie istnieje',
                    'cluster': cluster_name,
                    'service': service_name
                })
            }
        
        # 🔔 Krytyczny błąd - wyślij metrykę do alarmu w konsoli
        put_stop_failure_metric(cluster_name, service_name, region)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'cluster': cluster_name,
                'service': service_name,
                'console_alarm_triggered': True
            })
        }
        
    except Exception as e:
        error_message = f"Unexpected error: {str(e)}"
        logger.error(f"❌ {error_message}", exc_info=True)
        
        # 🔔 Wyślij metrykę dla każdego nieoczekiwanego błędu
        put_stop_failure_metric(cluster_name, service_name, region)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'cluster': cluster_name,
                'service': service_name,
                'console_alarm_triggered': True
            })
        }
