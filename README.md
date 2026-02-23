# finpay-otelcol-monitoring

`finpay-otelcol` ポートフォリオの監視スタック（MVP）。
OpenTelemetry Collector を中心に、**break（意図的劣化）→ Alert検知 → normal復旧** を README だけで再現できる Helm umbrella chartを提供します

> MVP は `port-forward` 前提で外部公開はしません。

## What’s inside (MVP)

* **otelcol-gateway**: OTLP 入口（normal/break 切替） + health_check
* **Tempo**: traces backend
* **Loki**: logs backend (Grafana Explore で検索導線)
* **Prometheus**: scrape + `rules.yml` による Alert 評価(Loss系)
* **Grafana**: datasource / dashboard provisioning（Collector Health + Loss panels）

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
docs/
  runbooks
    loss-alerts.md
```

## Contracts

* Full design / contracts: `../finpay-otelcol/DESIGN.md`（またはルートリポの DESIGN.md）
* Runbook: `docs/runbook/loss-alerts.md`
  * このREADMEには**Quick Runbook(短い完走ルート)**を記載します。

## Prerequisites

必須
* `kubectl`(クラスタ接続済み)
* `helm`v3
任意
* `curl`
* `telemetrygen`(finpay-clientがなくてもトレースを流してLossアラートを再現するため)

telemetrygenの例(Collectorバージョンと合わせるのが安全)
```bash
go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@v0.122.0
```

## Quickstart (Helm)

> Namespace は例です。MVP では単一 `monitoring` に同梱します。

```bash
kubectl create ns monitoring || true

helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml

kubectl -n monitoring get pods -o wide
kubectl -n monitoring get svc
```
期待結果(成功条件)
* `kubectl get pods`で主要Podが`Running`
* `kubectl get svc`で`grafana / prometheus / tempo / loki / otelcol-gateway`が見える

## Access (port-forward)

```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
kubectl -n monitoring port-forward svc/prometheus 9090:9090
kubectl -n monitoring port-forward svc/tempo 3200:3200
kubectl -n monitoring port-forward svc/loki 3100:3100
kubectl -n monitoring port-forward svc/otelcol-gateway 13133:13133 4317:4317 4318:4318
```

* Grafana: [http://localhost:3000](http://localhost:3000)
* Prometheus: [http://localhost:9090](http://localhost:9090)
* Tempo: [http://localhost:3200](http://localhost:3200)
* Loki: [http://localhost:3100](http://localhost:3100)
* otelcol-gateway health: [http://localhost:13133](http://localhost:13133/health)

任意の疎通確認
```bash
curl -sf http://localhost:13133/healthz && echo "otelcol-gateway: OK"
curl -sf http://localhost:3100/ready && echo "loki:OK"
```
## Grafana login(MVP既定)

デモ容易性のためvalues.yamlでハードコードしています(外部公開しない前提)
* user:`admin`
* password:`admin`
> 将来はSecret化(別Issue)を推奨します。

## Post-install checks(監視が正常なこと)

1) Prometheus Targets
Prometheus -> Status -> Targets
期待結果
* `otelcol-gateway`が`UP`
* endpointが`http://otelcol-gateway:8888/metrics`

2) Rulesがロードされている
Prometheus -> Status -> Rules
期待結果
* group`otelcol-loss`が表示される
* Errorがない

3) Grafana Datasources / Dashboard
Grafana
* Data sourcesが`Prometheus / Tempo / Loki`で`OK`
* DashboardsにCollector Health (UID:collector-health)がある(Folder:`Finpay`)

## Demo: break → alert → restore (Quick Runbook)

このデモは、otelcol-gatewayにトレースを流し、意図的にloss(accepted - sent)を発生させてPrometheusのLoss系アラートがPending→Firingになることを確認します。

1) `otelcol.mode=normal`で開始
```bash
helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml \
  --set otelcol.mode=normal
```
期待結果
* `otelcol-gateway`が再デプロイされる場合はrolloutして`Running`に戻る

1) `otelcol.mode=break`に切り替え
```bash
helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml \
  --set otelcol.mode=break
```
期待結果
* `otelcol-gateway`がrolloutしてbreak設定になる

3) トレースを2分以上流す
A. finpay-client
* retry stormを2分以上実行

B. telemetrygen
```bash
telemetrygen traces --otlp-endpoint localhost:4317 --otlp-insecure --rate 10 --duration 3m
```
* Alertは`for: 60s`→条件が60秒以上継続したら発火
* さらにrecording ruleが`rata(...[1m])`を使うため、値が揺れたり空になることがあります

4) Alertsを確認(Pending->Firing)
Prometheus->Alerts[http://localhost:9090](http://localhost:9090)
* `OtelcolLossRatioHigh`（warning）
* `OtelcolLossRatioCritical` (critical)
* `OtelcolLossSpansCritical` (critical)

期待結果
* 最初は`Pending`
* 条件成立が継続すると`Firing`
補足
* `OtelcolLossSpansCritical`(loss_spans/s > 200)は`--rate 10`だと越えにくいです。確実に見る場合は`--rate`をあげてください(例：`--rate 500`)

5) restore(normalに戻す)→収束確認
```bash
helm upgrade --install finpay-otelcol ./charts/finpay-otelcol \
  -n monitoring \
  -f ./charts/finpay-otelcol/values.yaml \
  --set otelcol.mode=normal
```
期待結果
* `otelcol-gateway`が `Running 1/1`
* `/alerts`が時間経過で `Firing -> Inactive`に戻る (`rate[1m]`のため1~2分遅れて収束することがあります)

Logs:Lokiを1クエリで確認(導線)
Grafana→Explore→Lokiで例

* `{app="otelcol-gateway"}`
もしラベルが違う場合はまず`{}`で出してから絞り込んでください(例：`|="otelcol-gateway"`)
期待結果
* otelcol-gatewayのログがヒットする

Alerts (Loss rules)

* `accepted_spans/s` = `rate(otelcol_receiver_accepted_spans[1m])`
* `sent_spans/s` = `rate(otelcol_exporter_sent_spans[1m])`
* `loss_spans/s` = `accepted - sent`
* `loss_ratio%` = `100 * loss / clamp_min(accepted, 1)`

Thresholds（MVP既定）:

* warning: `loss_ratio% > 5` for 60s
* critical: `loss_ratio% > 20` for 60s
* critical: `loss_spans/s > 200` for 60s

Troubleshooting
* `/targets`がUPなのに`rate(otelcol_receiver_accepted_spans[1m])`がEmpty
  * トレースが流れていない(telemetrygen実行、otelcol-gatewayのport-forward(4317)を確認)
* `otelcol_loss_spans:rate1m)`がEmpty
  * accepted/sentのラベル不一致の可能性→recording ruleを集約してから差分(当リポジトリは`sum by(job,instance)`済み)
* break切り替え後にotelcol-gatewayがCrashLoopBackOff
  * config内のenv参照が不正(`{env:VAR:-default}`形式にする)

詳細手順は [docs/runbooks/loss-alerts.md](docs/runbooks/loss-alerts.md) を参照してください。


## CI (example)

* `helm lint`
* `helm template` + `kubeconform`（rendered manifest validation）

## Tag policy

* **No `:latest`**
* Use SemVer tags (`v0.1.0`, ...)

## License

MIT
