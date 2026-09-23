# 最初のPlusCalモデル

`ClaimOneName.tla`は、同じ名前の所有recordをAとBが同時に取ろうとする場合だけを扱う。両方が空を見ても、原子的なno-replace発行で成功できるのは片方だけ、という安全性をTLCで検査する。Pi起動、Herdr pane、lock、世代、失敗時の資産保持は**まだモデル化しない**。TLCはRuby実装が仕様通りかを保証しない。

必要なものはJava 11以上と[公式リリース](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4)の`tla2tools.jar`だけ。この環境ではJava `temurin-21.0.12+8.0.LTS`を`mise`のユーザー領域に、jar v1.7.4を`~/.local/share/tlaplus/v1.7.4/tla2tools.jar`に置いた（SHA-256: `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`）。リポジトリにjarは含めない。

リポジトリのルートから、**正常なモデルの検査だけ**を実行する:

```sh
bundle exec rake model
```

PlusCalの変換とTLCの検査を順に行う。`No error has been found`が出れば合格。失敗例の作成・検査は含めない。このタスクはJavaが必要なため、通常の`rake`やCIには含めない。変換器は`.tla`内の`BEGIN TRANSLATION`以降を生成し直すので、PlusCalを編集した場合は生成差分も確認する。`spec/*.old`のバックアップはGitから除外している。

PlusCalは`(* --algorithm`から`end algorithm; *)`まで。変換器が書く`BEGIN TRANSLATION`以降は手で編集しない。TLCは`ClaimOneName.cfg`の3つの不変条件を調べる。正常なモデルは14個の到達状態でエラーなし。検査が形だけでないことを確かめるため、一時コピーで`Publish`時の`recordOwner = "none"`条件を除いたところ、TLCが`NeverTwoPublished`違反を報告した。この変更は本体には残していない。
