# Amazon Bedrock Model Access Setup

Enable Anthropic Claude models in **us-west-2** for the GovCloud demo environment.

> **Note:** Cross-region inference profiles (`us.*` prefix) are recommended over
> single-region model IDs. They provide better availability by automatically
> routing requests to less-busy regions within the US.

## Step 1 — Request Model Access

1. Sign in to the **AWS Console** → navigate to **Amazon Bedrock** → **Model access** (left sidebar) in the **us-west-2** region.
2. Click **Manage model access** (or **Modify model access**).
3. Scroll to the **Anthropic** section and enable the following models:
   - **Claude Sonnet 4.6**
   - **Claude Opus 4.6**
   - **Claude Haiku 4.5**
4. Click **Request model access** / **Save changes**.
5. If prompted, complete the **Anthropic First-Time Use (FTU)** form. This is a one-time per-account requirement — once submitted and approved, it covers all Anthropic models.
6. Wait for the status to change to **Access granted**. On-demand access is usually granted immediately.

## Step 2 — Verify Access via CLI

List available Anthropic models:

```bash
aws bedrock list-foundation-models \
  --region us-west-2 \
  --by-provider anthropic \
  --query "modelSummaries[*].modelId"
```

Confirm the three models appear in the output.

## Step 3 — Test Inference

Use the **cross-region inference profile IDs** for all API calls:

| Model | Cross-Region Inference Profile ID |
|---|---|
| Claude Sonnet 4.6 | `us.anthropic.claude-sonnet-4-6` |
| Claude Opus 4.6 | `us.anthropic.claude-opus-4-6-v1` |
| Claude Haiku 4.5 | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |

### Quick test with the AWS CLI

```bash
aws bedrock-runtime invoke-model \
  --region us-west-2 \
  --model-id us.anthropic.claude-haiku-4-5-20251001-v1:0 \
  --content-type application/json \
  --accept application/json \
  --body '{
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 128,
    "messages": [
      {"role": "user", "content": "Say hello in one sentence."}
    ]
  }' \
  /dev/stdout | jq .
```

### Quick test with Python (boto3)

```python
import json, boto3

client = boto3.client("bedrock-runtime", region_name="us-west-2")

response = client.invoke_model(
    modelId="us.anthropic.claude-haiku-4-5-20251001-v1:0",
    contentType="application/json",
    accept="application/json",
    body=json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 128,
        "messages": [
            {"role": "user", "content": "Say hello in one sentence."}
        ],
    }),
)

print(json.loads(response["body"].read()))
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AccessDeniedException` on invoke | Model access not yet granted — check the Bedrock console. |
| Model ID not in `list-foundation-models` | Ensure you are querying `us-west-2` and the FTU form is approved. |
| Throttling / `ThrottlingException` | Switch to cross-region inference profile IDs (`us.*`) for automatic load balancing. |
