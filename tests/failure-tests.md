# Failure Tests

1. Stop one application instance and verify the Auto Scaling Group replaces it.
2. Mark an ALB target unhealthy and verify traffic moves to a healthy target.
3. Block direct internet access to an app instance and verify the ALB remains the public entry point.
4. Verify the DB cannot be reached from the public subnet.
