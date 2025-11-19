import boto3
import os
import json

sqs = boto3.client("sqs")
queue_url = os.environ["QUEUE_URL"]

def handler(event, context):
    for record in event["Records"]:
        if record["eventName"] not in ["INSERT", "MODIFY"]:
            continue

        new = record["dynamodb"]["NewImage"]

        message = {
            "accountUserId": new["account_user_id"]["S"],
            "exchange": new["exchange"]["S"],
            "symbol": new["symbol"]["S"]
        }

        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message)
        )

    return {"status": "ok"}
