# alb-ingress

Add this chart as an umbrella dependency to define an application's HTTPS
routes on an existing AWS Load Balancer Controller IngressClass. The class
supplies load balancer settings such as scheme, certificates, and IP target type.

```yaml
dependencies:
  - name: alb-ingress
    version: 0.1.0
    repository: oci://ghcr.io/marxbiotech/helm-charts
    condition: alb-ingress.enabled
```

Set the class and host in each environment's umbrella values. A route can
reference an existing Service. Define a Service under `services` when the
ALB target group needs its own port or health check.

```yaml
alb-ingress:
  enabled: true
  ingress:
    name: app-alb
    className: internal-apps
    hostname: app.example.com
    paths:
      - path: /
        pathType: Prefix
        serviceName: web-alb
        servicePort: 8080
  services:
    web-alb:
      selector:
        app: web
      port: 8080
      targetPort: 8080
      healthCheckPath: /health
```

The controller uses the Service name and port for each route. Optional target
Services select existing pods. The chart is disabled by default so an umbrella
can enable it independently in each environment.
