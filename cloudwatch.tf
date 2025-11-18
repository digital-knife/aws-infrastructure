#SNS TOPIC - Alert Notifs
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "jermainerakoczy1@gmail.com"
}

# CLOUDWATCH DASHBOARD
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }]
          ]
          period = 300
          region = var.aws_region
          title  = "EC2 CPU Utilization"
        }
      }
    ]
  })
}


#Alarms: High CPU
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when CPU > 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

#Alarm ALB 500 errors
resource "aws_cloudwatch_metric_alarm" "alb_500" {
  alarm_name          = "${local.name_prefix}-alb-500"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Triggers when 5xx errors > 10 in 5 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags

}

#Alarm: unhealthy targets
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${local.name_prefix}-unhealthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "Triggers when healthy targets < 2"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.web.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}

# Alarm: httpd service down
resource "aws_cloudwatch_metric_alarm" "httpd_down" {
  alarm_name          = "${local.name_prefix}-httpd-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "httpd_status"
  namespace           = "CustomMetrics/${var.environment}"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Triggers when httpd service stops"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"

  tags = local.common_tags
}
