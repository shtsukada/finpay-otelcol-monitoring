# finpay-otelcol-monitoring

`finpay-otelcol` ポートフォリオの監視スタック（MVP）。
OpenTelemetry Collector を中心に、**break（意図的劣化）→ Alert検知 → normal復旧** を再現できる Helm umbrella chartを提供します

## What’s inside (MVP)

* **otelcol-gateway**: OTLP 入口（normal/break 切替）
* **Tempo**: traces backend
* **Prometheus**: scrape + `rules.yml` による Alert 評価
* **Grafana**: datasource / dashboard provisioning（Collector Health + Loss panels）

> MVP は `port-forward` 前提で外部公開はしません。

## Repository layout

```txt
charts/finpay-otelcol/
  Chart.yaml
  values.yaml
  values.schema.json
  templates/
files/
  prometheus/
    rules.yml
```

## Contracts

* Full design / contracts: `../finpay-otelcol/DESIGN.md`（またはルートリポの DESIGN.md）
* Runbook: `../finpay-otelcol/docs/runbook.md`

## Quickstart (Helm)

> Namespace は例です。MVP では単一 `monitoring` に同梱します。

```bash
kubectl create ns monitoring || true

helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml
```

## Access (port-forward)

```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
kubectl -n monitoring port-forward svc/prometheus 9090:9090
kubectl -n monitoring port-forward svc/tempo 3200:3200
```

* Grafana: [http://localhost:3000](http://localhost:3000)
* Prometheus: [http://localhost:9090](http://localhost:9090)
* Tempo: [http://localhost:3200](http://localhost:3200)

## Demo: break → alert → recover

1. Start with `otelcol.mode=normal`
2. Switch to `otelcol.mode=break`（GitOps: PR → merge → Argo sync、または Helm）
3. `finpay-client` の retry storm を **5分以上**実行
4. Prometheus `/alerts` で FIRING を確認

   * `OtelcolLossRatioHigh`（warning）
   * `OtelcolLossRatioCritical` / `OtelcolLossSpansCritical`（条件により）
5. `otelcol.mode=normal` に戻し、alert が Inactive 方向へ戻ることを確認

### Switch by Helm

```bash
# break
helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml \
  --set otelcol.mode=break

# normal
helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml \
  --set otelcol.mode=normal
```

## Alerts (rules.yml)

`files/prometheus/rules.yml` で **Loss** を定義します。

* `accepted_spans/s` = `rate(otelcol_receiver_accepted_spans[1m])`
* `sent_spans/s` = `rate(otelcol_exporter_sent_spans[1m])`
* `loss_spans/s` = `accepted - sent`
* `loss_ratio%` = `100 * loss / clamp_min(accepted, 1)`

Thresholds（MVP既定）:

* warning: `loss_ratio% > 5` for 5m
* critical: `loss_ratio% > 20` for 5m
* critical: `loss_spans/s > 200` for 5m

## CI (example)

* `helm lint`
* `helm template` + `kubeconform`（rendered manifest validation）

## Tag policy

* **No `:latest`**
* Use SemVer tags (`v0.1.0`, ...)

## License

MIT
