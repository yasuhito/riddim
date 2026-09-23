# Pi停滞の再現・診断ラボ

Firstmateの`bin/fm-spawn.sh`はPiの`agent_start`、`agent_settled`、`turn_end`を記録し、`bin/fm-watch.sh`の`busy_turn_over_age`は進捗なしのbusy turnを監視する。`tests/fm-watch-triage.test.sh`には時計を使った監視テストがある。一方、APIが応答しないPiリクエストのローカル再現には直接使えないため、独立した最小限のラボを置く。Riddimのworker監視や自動interruptは追加しない。

```sh
ruby scripts/pi_stall_lab.rb reproduce
ruby scripts/pi_stall_lab.rb replay /path/to/pi-session.jsonl
ruby scripts/pi_stall_lab.rb observe /path/to/worker.brief.trace.<spawn_gen>.jsonl
```

`reproduce`は、一時的なPi設定、ダミー鍵、127.0.0.1のOpenAI互換サーバーで本物のPiを起動する。正常なストリームで`OK`を返す対照試験の後、HTTPリクエストを受け取って応答せず2秒待つ。後者ではPiが生存し、stdoutに回答がないことを検証する。3つ目のケースでは、リクエストを受け取った直後にHTTP 200の`text/event-stream`ヘッダーだけを送信してflushし、SSE本文は1バイトも送らず2秒待つ。ここではPiが生存し、stdoutが空で、generationローカルのtraceに`request_prepared`と`response_headers`が記録され、`first_update`・`turn_end`・`agent_settled`が出ないことを検証する。子プロセスは終了させ、一時ファイルを消す。実際の提供元や既存のHerdr pane・ownership recordは使わない。通常のCIとは別に手動で実行する。

`replay`はPiの保存済みJSONLから、直前のmessageと空の`aborted`応答の間隔だけを表示する。本文・認証情報は表示せず、入力ファイルも変更しない。元の事象では`toolResult`後324秒、次の`user`後187秒を再検出できた。

次のRiddim task workerを**明示的に計測するときだけ**、起動コマンドに`RIDDIM_PI_TRACE=1`を付ける。例: `RIDDIM_PI_TRACE=1 bin/riddim start worker --worktree --task-file task.md`。一時的なPi拡張が、briefと同じprivate stateディレクトリに、recordの`spawn_gen`を含む`worker.brief.trace.<spawn_gen>.jsonl`を新規作成する。`observe`で実行中にも確認できる。本文、HTTPヘッダー、認証情報、モデル名は記録しない。既存のPiには後付けできず、traceが未作成なら計測が始まった証拠はない。ファイルは自動消去せず、workerと一緒に保持する。native taskなしの起動には付かない。

イベントは`request_prepared`（Piがprovider payloadを組み立て、送信直前）、`response_headers`（HTTP応答ヘッダーをPiが受信）、`first_update`（最初のPi assistantストリーム更新）、`turn_end`、`agent_settled`など。`request_prepared`はproviderへの到達を証明しない。`response_headers`が出ないだけではネットワーク/API待ちとPi内部・非対応providerを区別できない。`first_update`は最初のHTTPバイトそのものではない。進捗を推測で埋めず、実記録の時刻で判断する。trace単独は現在のPiの生存やtask完了の証拠ではないので、recordが指すexact paneの状態も別に確認する。再送、interrupt、再起動は行わない。

`headers_only`ケースが示す証拠の境界はここまでである。ヘッダー後のPi静止は「レスポンスヘッダーまではPiの外から観測可能な形で届いた」ことまでしか証明しない。ヘッダー後にサーバーが本文バイトを送っても、PiがSSEイベントとして解釈できなければ`first_update`は出ないため、`first_update`なしは「ヘッダー後にAPIバイトが届いていない」ことの証明にならない。TCP接続が生きていることと、Piがヘッダー後にソケットを読み続けていることも、このケースでは検証しない。元の停滞がヘッダー前か後かを切り分ける目安にはなるが、障害位置の確定にはネットワークパケットやprovider側の記録など別の観測が必要である。

実Herdr検証（2026-09-23、専用session `riddim`）: 一時Git repoの新しいworktree workerを明示的なtrace付きで起動した。exact paneでPiの登録を確認し、0600の世代別traceに`request_prepared`、`response_headers`、`first_update`、`turn_end`、`agent_settled`が順番に記録された。合成タスクへの返信をPiセッションで確認し、`agent-state=alive`、`busy-state=idle`も別々に確認した。これは正常な短いturnの検証であり、元の停滞の原因を示さない。

**限界:** ローカル試験が再現するのは「リクエスト後、APIから何も届かずPiが待つ」という症状であり、元の停滞が提供元、ネットワーク、Pi内部のどこで起きたかは証明しない。Pi JSONLに応答がないことも、未到達とAPI待ちを区別しない。再発時は中断前に、requestの到達・最初の応答バイト・Piのturn境界を別々に観測する必要がある。実セッションや認証情報をラボへコピーしない。
