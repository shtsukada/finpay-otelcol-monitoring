# Runbook:Loss rules/alerts(break→firing→restore)

このRunbookは、otelcol-gatewayにトレースを流し、意図的にloss(accepted - sent)を発生させて、PrometheusのLoss系アラートがPending→Firingになることを確認しています。

## 前提

* Namespace: monitoring
* Pod: otelcol-gateway,prometheus,grafana,tempoが存在
* Prometheusがotelcol-gateway:8888/metricsをscrapeしている(TargetがUP)
* values/テンプレで以下が成立していること
  * Prometheus rulesがロードされている(otelcol-lossグループが/rulesに表示)
  * recording rules:
    * otelcol:accepted_spans:rate1m
    * otelcol:sent_spans:rate1m
    * otelcol:loss_spans:rate1m
    * otelcol:loss_ratio

## 1.状態確認(Targets/Rules)

1-1)監視Pod確認
kubectl -n monitoring get pods

期待結果

* otelcol-gatewayがRunning 1/1
* finpay-otelcol-prometheusがRunning 1/1

1-2)Prometheus Targets確認(UP)
kubectl -n monitoring port-forward deploy/finpay-monitoring-finpay-otelcol-prometheus 9090:9090

ブラウザ：<http://localhost:9090/targets>

期待結果

* otelcol-gatewayのtargetがUP
* endpoint:<http://otelcol-gateway:8888/metrics>

1-3)Rulesロード確認
ブラウザ：<http://localhost:9090/rules>

期待結果

* group:otelcol-lossが表示
* rules/alertsがOK(Errorなし)

## 2.breakモードでlossを発生させる

2-1)otelcolをbreakモードへ切り替え(GitOps)

values
  otelcol:
    mode: break

commit →merge →Argo CD sync

期待結果

* otelcol-gatewayがrolloutし、再びRunning 1/1で安定する

## 3.トレースを継続送信してPending→Firingを作る

3-1)telemetrygenで60秒以上トレース送信(for:60sを満たすため)
telemetrygen traces \
  --otlp-endpoint localhost:4317 \
  --otlp-insecure \
  --rate 10 \
  --duration 180s

期待結果

* Prometheus Graphで以下が値を返す(Result series >= 1)
  * otelcol:accepted_spans:rate1m
  * otelcol:sent_spans:rate1m
  * otelcol:loss_spans:rate1m
  * otelcol:loss_ratio
* /alertsでLoss系がPending→Firingになる

## 4.Prometheus Alerts(Pending→Firing)確認

ブラウザ：<http://localhost:9090/alerts>
期待結果(例)

* OtelcolLossRatioHigh(loss_ratio > warn):
  * 状態：FIRING
* OtelcolLossRatioCritical(loss_ratio > critical):
  * 状態：FIRING
* OtelcolLossSpansCritical(loss_spans > spansCritical):
  * 状態：トラフィック次第(rate 10 だと閾値200/sは超えにくい)

## 5.復旧(restore)

5-1)telemetrygenを停止
--durationが終わるのを待つ or Ctrl+c

5-2)otelcolをnormalに戻す(GitOps)

  otelcol:
    mode: normal

commit →merge →Argo CD sync

期待結果

* otelcol-gateway が Running 1/1
* /alerts が時間経過で FIRING → Inactive に戻る（rate[1m] のため 1〜2分程度遅れて収束することがあります）

トラブルシュート

* /targets が UP なのに rate(otelcol_receiver_accepted_spans[1m]) が Empty
  * トレースが流れていない（telemetrygen 実行/port-forward を確認）
* otelcol:loss_spans:rate1m が Empty
  * accepted/sent のラベルが揃っていない可能性 → recording rule を sum by(job,instance) などで集約してから差分を取る
* break 切替後に otelcol-gateway が CrashLoopBackOff
  * config 内の env 参照が不正（${env:VAR:-default} 形式にする）
