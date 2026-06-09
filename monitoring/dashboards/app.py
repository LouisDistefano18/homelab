import datetime
import os
from functools import wraps

import boto3
from flask import Flask, Response, render_template_string, request

app = Flask(__name__)

# --- Basic Auth ---
DASHBOARD_USER = os.environ.get("DASHBOARD_USER", "louis")
DASHBOARD_PASS = os.environ.get("DASHBOARD_PASS")

# Refuse to start without a password rather than falling back to a blank one.
if not DASHBOARD_PASS:
    raise RuntimeError("DASHBOARD_PASS is not set — refusing to start without a dashboard password.")

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or auth.username != DASHBOARD_USER or auth.password != DASHBOARD_PASS:
            return Response(
                "Authentication required.",
                401,
                {"WWW-Authenticate": 'Basic realm="Homelab Dashboard"'}
            )
        return f(*args, **kwargs)
    return decorated

HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Homelab Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0d1117; color: #e6edf3; padding: 20px; }
        h1 { color: #58a6ff; font-size: 1.4em; margin-bottom: 4px; }
        .subtitle { color: #8b949e; font-size: 0.85em; margin-bottom: 24px; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 12px; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 10px; padding: 16px; }
        .card.full { grid-column: 1 / -1; }
        .card-title { color: #8b949e; font-size: 0.75em; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; }
        .card-value { font-size: 1.4em; font-weight: 600; }
        .running { color: #3fb950; }
        .stopped { color: #f85149; }
        .pending { color: #d29922; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.75em; font-weight: 600; }
        .badge.running { background: #0d4429; color: #3fb950; }
        .badge.stopped { background: #3d1a1a; color: #f85149; }
        table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        th { color: #8b949e; text-align: left; padding: 6px 0; border-bottom: 1px solid #30363d; font-weight: 500; }
        td { padding: 8px 0; border-bottom: 1px solid #21262d; }
        .refresh { color: #8b949e; font-size: 0.75em; margin-top: 16px; text-align: center; }
        .error { color: #f85149; }
    </style>
</head>
<body>
    <h1>Homelab Dashboard</h1>
    <p class="subtitle">{{ timestamp }}</p>

    {% if error %}
    <div class="card">
        <div class="card-title">Error</div>
        <div class="error">{{ error }}</div>
    </div>
    {% else %}
    <div class="grid">
        <div class="card">
            <div class="card-title">EC2 State</div>
            <div class="card-value {{ instance.state }}">{{ instance.state }}</div>
        </div>
        <div class="card">
            <div class="card-title">Instance Type</div>
            <div class="card-value">{{ instance.type }}</div>
        </div>
        <div class="card">
            <div class="card-title">Public IP</div>
            <div class="card-value" style="font-size:1em">{{ instance.public_ip }}</div>
        </div>
        <div class="card">
            <div class="card-title">Availability Zone</div>
            <div class="card-value" style="font-size:1em">{{ instance.az }}</div>
        </div>
        <div class="card full">
            <div class="card-title">S3 Log Bucket</div>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Bucket</td><td>{{ s3.bucket }}</td></tr>
                <tr><td>Total Objects</td><td>{{ s3.count }}</td></tr>
                <tr><td>Total Size</td><td>{{ s3.size }}</td></tr>
            </table>
        </div>
        <div class="card full">
            <div class="card-title">Instance Details</div>
            <table>
                <tr><th>Field</th><th>Value</th></tr>
                <tr><td>Instance ID</td><td>{{ instance.id }}</td></tr>
                <tr><td>Name</td><td>{{ instance.name }}</td></tr>
                <tr><td>Launch Time</td><td>{{ instance.launch_time }}</td></tr>
                <tr><td>AMI</td><td>{{ instance.ami }}</td></tr>
            </table>
        </div>
    </div>
    {% endif %}
    <div class="refresh">Auto-refreshes every 60 seconds</div>
    <script>setTimeout(() => location.reload(), 60000);</script>
</body>
</html>
"""

@app.route("/")
@require_auth
def dashboard():
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        ec2 = boto3.client("ec2", region_name="us-east-1")
        s3  = boto3.client("s3", region_name="us-east-1")

        resp = ec2.describe_instances(Filters=[{"Name": "tag:Name", "Values": ["homelab-server-01"]}])
        inst = resp["Reservations"][0]["Instances"][0]
        name = next((t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"), "N/A")

        instance = {
            "id":          inst["InstanceId"],
            "name":        name,
            "state":       inst["State"]["Name"],
            "type":        inst["InstanceType"],
            "public_ip":   inst.get("PublicIpAddress", "N/A"),
            "az":          inst["Placement"]["AvailabilityZone"],
            "launch_time": str(inst["LaunchTime"].strftime("%Y-%m-%d %H:%M:%S")),
            "ami":         inst["ImageId"]
        }

        paginator = s3.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket="louislab-logs")
        total_size = 0
        total_count = 0
        for page in pages:
            for obj in page.get("Contents", []):
                total_size  += obj["Size"]
                total_count += 1

        s3_data = {
            "bucket": "louislab-logs",
            "count":  total_count,
            "size":   f"{round(total_size / 1024, 2)} KB"
        }

        return render_template_string(HTML, timestamp=timestamp, instance=instance, s3=s3_data, error=None)

    except Exception as e:
        return render_template_string(HTML, timestamp=timestamp, instance=None, s3=None, error=str(e))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)