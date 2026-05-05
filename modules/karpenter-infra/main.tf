locals {
  name = "${var.project_name}-${var.environment}"
}

# ── SQS Queue cho Karpenter Interruption Handling ─────────────────────────────
resource "aws_sqs_queue" "karpenter" {
  name                      = "${local.name}-karpenter-interruption"
  message_retention_seconds = 300 # 5 phút là đủ cho interruption events
  sqs_managed_sse_enabled   = true

  tags = { Name = "${local.name}-karpenter-interruption" }
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeToSend"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter.arn
      },
      {
        Sid       = "AllowEC2InterruptionService"
        Effect    = "Allow"
        Principal = { Service = "sqs.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

# ── EventBridge Rules → SQS ───────────────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name}-karpenter-spot-interruption"
  description = "Spot Instance Interruption Warning → Karpenter SQS"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${local.name}-karpenter-rebalance"
  description = "EC2 Instance Rebalance Recommendation → Karpenter SQS"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule = aws_cloudwatch_event_rule.rebalance.name
  arn  = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "instance_state" {
  name        = "${local.name}-karpenter-instance-state"
  description = "EC2 Instance State-change → Karpenter SQS"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
}

resource "aws_cloudwatch_event_target" "instance_state" {
  rule = aws_cloudwatch_event_rule.instance_state.name
  arn  = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "${local.name}-karpenter-scheduled-change"
  description = "AWS Health Scheduled Change → Karpenter SQS"

  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
    detail = {
      service = ["EC2"]
    }
  })
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule = aws_cloudwatch_event_rule.scheduled_change.name
  arn  = aws_sqs_queue.karpenter.arn
}
