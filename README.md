# ops-lab

Linuxサーバー運用で発生する監視・バックアップ・定期処理を自動化した小規模なOps環境。

Bash、cron、Dockerを利用し、
運用時に必要となる監視・通知・ログ管理・自動処理を構築しています。

単純なスクリプト実行ではなく、
- 状態を管理すること
- 必要なタイミングだけ通知すること
- 異常発生時に原因調査できること
- 同じ環境を再構築できること

を意識して設計しています。

---

## Overview

実装内容:

- ディスク使用率監視
- 状態管理型アラート通知
- 復旧通知
- 定期バックアップ
- cronによるスケジュール駆動型実行（5分間隔 / 毎日9時）
- ログ管理
- Dockerによる実行環境構築

---

## Architecture
```bash
Dockerfile
 |
 +-- Ubuntu 24.04ベース環境
 +-- cron実行環境(Ubuntu+cron+tools)
 +-- Bash実行環境
 +-- 必要パッケージ導入（curl / git / jq / tzdata / cron）
 +-- ユーザー作成（r.h）
 +-- タイムゾーン設定（Asia/Tokyo）
 +-- スクリプト一括配置（docker/配下）
 +-- entrypointでcron登録 + 起動制御

        ↓

docker-compose
 |
 +-- コンテナ起動
         ↓

entrypoint.sh
 |
 +-- crontab登録
 +-- cronデーモン起動（cron -f）

        ↓

cron
 |
 +-- disk_monitor.sh
 |       |
 |       +-- ディスク使用率取得
 |       +-- 状態判定（OK / WARN / CRITICAL）
 |       +-- 状態ファイル比較
 |       +-- Slack通知（状態変化時のみ）
 |       +-- monitor.log出力
 |
 +-- backup.sh
         |
         +-- index.htmlバックアップ
         +-- タイムスタンプ付与
         +-- 世代管理
         +-- backup.log出力
         +-- エラー時Slack通知
```

---

## Features

## Disk Monitoring

`disk_monitor.sh`

ディスク使用率を定期的に確認し、
状態に応じた通知を行います。

監視状態

- OK
- WARN
- CRITICAL

単純な閾値通知ではなく、
現在状態と前回状態を比較する状態管理方式を採用しています。

状態変化時のみ通知することで、
同じ警告を繰り返し送信する通知ノイズを削減しています。

また、警告状態から復旧した場合は復旧通知を送信します。

---

## Backup Automation

`backup.sh`

指定したファイルを定期的にバックアップします。

実装:

- タイムスタンプ付きバックアップ
- 世代管理（保持数制御）
- ログ保存
- エラー検知
- Slack通知
- DRY RUNによる動作確認対応

cron環境で動作することを前提に、
環境変数読み込みやログ確認などの調整を行っています。

---

## Environment

使用技術

- Linux (Ubuntu)
- Bash
- Docker
- Docker Compose
- Dockerfileによる環境構築
- cron
- Slack Incoming Webhook
- Git / GitHub

---

## Files

各ファイルの役割

* [01_env.example: 環境設定例](./01_env.example)
* [02_cronjob.txt: cron自動実行設定](./02_cronjob.txt)
* [03_disk_monitor.sh: ディスク監視スクリプト](./03_disk_monitor.sh)
* [04_backup.sh: バックアップ自動化スクリプト](./04_backup.sh)
* [05_index.html: バックアップ検証対象](./05_index.html)

---

## Logs

生成されるログ

- monitor.log        ディスク監視ログ
- backup.log         バックアップ実行ログ
- cron実行ログ       cronによる実行確認用

---

## Design Points

### State-based Monitoring

監視では単純な数値判定ではなく、
状態管理による通知制御を採用しています。

前回状態との差分を確認することで、
不要な通知を削減し、運用時の確認負荷を減らしています。

---

### Error Handling

処理失敗時に原因調査できるよう、ログ出力・エラー検知・通知処理を実装しています。

---

### Configuration Separation

Webhook URLなどの設定値は
コードから分離して管理しています。

環境情報と処理内容を分けることで、
管理しやすい構成にしています。

---

### Reproducible Environment

DockerfileとDocker Composeを利用し、
実行環境をコードとして管理しています。

環境差による動作不一致を減らし、
同じ環境を再構築できる構成にしています。

---

## Future Improvements

- クラウド環境での監視基盤構築
- IaCによるインフラ構築
- メトリクス可視化
- より実運用に近いアラート設計

---

## Purpose
SRE / DevOps領域で扱われる、
監視・通知・自動化・環境再現性を意識した運用設計を実践しています。
