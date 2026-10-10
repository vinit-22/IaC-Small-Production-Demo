import base64
import json
import logging
import os
import re
import uuid

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]
MAX_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", "5242880"))
ALLOWED_EXT = {".txt", ".csv", ".json", ".png", ".jpg", ".jpeg", ".pdf"}


def _resp(code, body):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    raw_name = params.get("filename", "")
    body = event.get("body")

    if not raw_name:
        return _resp(400, {"error": "missing ?filename= query parameter"})
    if body is None or body == "":
        return _resp(400, {"error": "empty body"})

    # Sanitise the filename (no paths, no odd characters)
    name = os.path.basename(raw_name)
    name = re.sub(r"[^A-Za-z0-9._-]", "_", name)
    ext = os.path.splitext(name)[1].lower()
    if ext not in ALLOWED_EXT:
        return _resp(400, {"error": f"extension {ext or '(none)'} not allowed",
                           "allowed": sorted(ALLOWED_EXT)})

    data = base64.b64decode(body) if event.get("isBase64Encoded") else body.encode("utf-8")
    if len(data) > MAX_BYTES:
        return _resp(413, {"error": f"file exceeds {MAX_BYTES} bytes"})

    key = f"uploads/{uuid.uuid4().hex[:8]}-{name}"
    s3.put_object(Bucket=BUCKET, Key=key, Body=data, ServerSideEncryption="AES256")
    logger.info("Stored s3://%s/%s (%d bytes)", BUCKET, key, len(data))

    return _resp(200, {"message": "uploaded", "bucket": BUCKET, "key": key, "bytes": len(data)})
