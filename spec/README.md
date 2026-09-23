# 最初のPlusCalモデル

`ClaimOneName.tla`は、同じ名前の所有recordをAとBが同時に取ろうとする場合だけを扱う。両方が空を見ても、原子的なno-replace発行で成功できるのは片方だけ、という安全性をTLCで検査する。Pi起動、Herdr pane、lock、世代、失敗時の資産保持は**まだモデル化しない**。TLCはRuby実装が仕様通りかを保証しない。

必要なものはJava 11以上と[公式リリース](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4)の`tla2tools.jar`だけ。この環境ではJava `temurin-21.0.12+8.0.LTS`を`mise`のユーザー領域に、jar v1.7.4を`~/.local/share/tlaplus/v1.7.4/tla2tools.jar`に置いた（SHA-256: `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`）。リポジトリにjarは含めない。

リポジトリのルートから、**2つの正常なモデルの検査だけ**を実行する:

```sh
bundle exec rake model
```

それぞれPlusCalの変換とTLCの検査を順に行う。両方に`No error has been found`が出れば合格。失敗例の作成・検査は含めない。このタスクはJavaが必要なため、通常の`rake`やCIには含めない。変換器は`.tla`内の`BEGIN TRANSLATION`以降を生成し直すので、PlusCalを編集した場合は生成差分も確認する。`spec/*.old`のバックアップはGitから除外している。

PlusCalは`(* --algorithm`から`end algorithm; *)`まで。変換器が書く`BEGIN TRANSLATION`以降は手で編集しない。

## 同時に札を取る: ClaimOneName

TLCは`ClaimOneName.cfg`の3つの不変条件を調べる。正常なモデルは14個の到達状態でエラーなし。検査が形だけでないことを確かめるため、一時コピーで`Publish`時の`recordOwner = "none"`条件を除いたところ、TLCが`NeverTwoPublished`違反を報告した。この変更は本体には残していない。

## 古い片付けから新しい札を守る: ProtectNewGeneration

台帳の同じ名前の欄（`state/<name>.meta`）に、最初は旧世代`old`の記録がある。`proper`は旧世代の記録を正しく消し、欄が空いたときだけ`new`が新世代の記録を発行する。一方`late`は旧世代の番号を持ったまま、遅れて片付けに来る。3者の実行順をTLCが入れ替え、**新世代の発行後は欄が`new`のまま**という`NewRecordSurvives`を検査する（11個の到達状態）。`late`が新世代の発行後に来る順も含む。

各操作は名前ごとのlockを保持する一つの原子的な手順として扱う。削除前の世代照合と削除の間に、協調する別の操作は割り込めない。Herdr paneの確認、壊れた記録、非協調プロセス、世代番号の生成方法はモデル化しない。Firstmateは`fm-spawn.sh`で再起動ごとに`spawn_gen`を記録し、`fm-backlog-transition-lib.sh`では古い世代のclose記録を現在の世代と照合して無効化する。Riddimはその小さいsubsetで、`lib/riddim/start.rb`の起動失敗後の片付けだけが、pane消滅を確認してから`lib/riddim/ownership/record.rb`で世代を照合し、名前のlock下で記録を削除する。Firstmateの再起動や全teardownを実装・検証したわけではない。

一時コピーだけで`late`の照合条件を「空でなければ消す」に変えて再変換・検査すると、`old`の削除、`new`の発行、遅れた`late`による`new`の削除という反例をTLCが報告する。本体には変更を残していない。モデルが合格してもRuby実装がその通り動く保証はないため、別途`test/ownership_test.rb`で旧世代の削除要求が新世代の記録を残すことを確認する。
