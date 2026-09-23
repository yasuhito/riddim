# 最初のPlusCalモデル

`ClaimOneName.tla`は、同じ名前の所有recordをAとBが同時に取ろうとする場合だけを扱う。両方が空を見ても、原子的なno-replace発行で成功できるのは片方だけ、という安全性をTLCで検査する。Pi起動、Herdr pane、lock、世代、失敗時の資産保持は**まだモデル化しない**。TLCはRuby実装が仕様通りかを保証しない。

必要なものはJava 11以上と[公式リリース](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4)の`tla2tools.jar`だけ。この環境ではJava `temurin-21.0.12+8.0.LTS`を`mise`のユーザー領域に、jar v1.7.4を`~/.local/share/tlaplus/v1.7.4/tla2tools.jar`に置いた（SHA-256: `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`）。リポジトリにjarは含めない。

リポジトリのルートから、一発で正常なモデルとわざと壊した一時コピーを検査できる:

```sh
./spec/check-claim
```

正常なモデルでは`No error has been found`、一時コピーでは`Invariant NeverTwoPublished is violated`とA・Bの順番を表示する。**この2つがそろって終了コード0**。一時コピーは自動で削除し、本物の`.tla`と`.cfg`は変更しない。

PlusCalを変更した後に手動で変換・検査する場合は、`spec/`に移動して以下を実行する:

```sh
cd spec
jar="$HOME/.local/share/tlaplus/v1.7.4/tla2tools.jar"
mise exec 'java@temurin-21.0.12+8.0.LTS' -- java -cp "$jar" pcal.trans ClaimOneName.tla
mise exec 'java@temurin-21.0.12+8.0.LTS' -- java -cp "$jar" tlc2.TLC -workers 1 ClaimOneName.tla
```

PlusCalは`(* --algorithm`から`end algorithm; *)`まで。変換器が書く`BEGIN TRANSLATION`以降は手で編集しない。TLCは`ClaimOneName.cfg`の3つの不変条件を調べる。正常なモデルは14個の到達状態でエラーなし。検査が形だけでないことを確かめるため、一時コピーで`Publish`時の`recordOwner = "none"`条件を除いたところ、TLCが`NeverTwoPublished`違反を報告した。この変更は本体には残していない。
