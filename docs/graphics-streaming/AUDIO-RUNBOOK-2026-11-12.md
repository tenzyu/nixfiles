# neko5 osu!lazer Audio 最適化・再開手順書（2026-11-12）

基準: `tenzyu/nixfiles` main `9a6125ab75caff3d36de05bbe2ae3bbf81cce953`（2026-11-12 push）。本書は Audio 経路の次の検討段階を指定する。Input/Update/Draw 上限、既存 OpenGL/Wayland/1280x720、Direct Scanout、内蔵 OTD、SplitCast のゲーム非干渉条件を変更しない。現行の SplitCast Capture は neko5 で無効のまま。

## 結論と根拠

1. `osu-audio-quantum-lab` は PipeWire のグラフ周期を設定するだけで、osu! の BASS デバイス周期を変更しない。2026-11-07の正本データは、`clock.force-quantum=0`でも実際の出力ノードが `256/48000` で稼働した例を示す。設定値 `0` を 1024 frames と同一視しない。
2. osu!framework `AudioManager.InitBass()` は既定で `Bass.DeviceBufferLength=10`、`Bass.UpdatePeriod=5`、`Bass.PlaybackBufferLength=100`を設定し、`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD`を使ったときに `Bass.Configure(DevicePeriod,N)` と `DeviceBufferLength=1`を要求する。デバイス初期化前の変更でのみ有効。
3. `SampleChannelBass.Play()` → `AudioComponent.EnqueueAction()` → Audio Threadでの`RunSynchronously()` → `BassAudioMixer.ChannelPlay()` → BASSミキサーという待機境界がある。`Play()`呼び出しは物理発音ではない。
4. BASS公式仕様では `BASS_CONFIG_DEV_PERIOD` の負値はサンプル数であり、実際の周期はドライバ側で丸められ得る。デバイスバッファは更新周期の2倍以上に丸められる。`-256`は 44.1kHzなら5.805ms、48kHzなら5.333msの更新周期要求で、最低バッファはそれぞれ約11.61ms、10.67msに相当する。実効値はこれだけで確定しない。
5. Linuxの上流報告 `ppy/osu/discussions/38001`（2026-06、osu!lazer 2026.518.0）には短周期設定でDT/NC切替などの際にBASSmixのSIGSEGVが起きた再現例がある。一方、osu!frameworkは2026-10-08にBASSライブラリを更新している（#6833）。neko5の現在の`libbassmix`で同じ不具合が残るかは未確認。初回は`-256`に限り、`-128`以下は後段の互換性検討に回す。

## 実行手順

### Step 0: 保全

Gitリポジトリの変更を確認し、パッチを適用する前に対象コミットとの一致を確認する。最新のmainは GitHub の commit `9a6125ab75caff3d36de05bbe2ae3bbf81cce953`。自動push、`nh os switch`、設定の恒久変更は不要。パッチ導入後、BASS試験はホーム設定の再ビルドを要しない。

### Step 1: 現在の状態を表示

osu!を終了し、リポジトリ直下で実行する。

```bash
bash scripts/osu-performance/bass-period-lab.sh status
```

`osu-lazer`が利用可能か、既存のBASS環境変数が設定されていないかを確認する。PipeWireの`force-quantum`が0以外なら、設定を勝手に変更しない。その変更元を確認してから比較条件を統一する。

### Step 2: 通常のBASS条件

```bash
bash scripts/osu-performance/bass-period-lab.sh baseline
```

ゲームを起動し、同じ譜面・同じMod・同じスキン・同じ音量でプレイする。リプレイを利用できる場合でも、入力操作時の聴感とは別の負荷として扱う。途中でグローバルOffsetや譜面Offsetを変更しない。ゲームを正常終了させる。

### Step 3: BASS周期 `-256` 条件

```bash
bash scripts/osu-performance/bass-period-lab.sh -256
```

ゲームを起動し、Step 2と同じ譜面・Mod・音量でプレイする。音切れ・クリック音・遅延感・連打感の差、曲の再生位置、音声装置の切断、ゲーム異常終了を記録する。通常終了で試験環境変数はゲームプロセスと共に消える。設定の恒久化や再起動は不要。

この2つの条件で自動化しているのは**BASS設定のリクエスト**であり、実際にその周期でハードウェアが稼働したことを示すものではない。`AudioManager`のログにある`Device period length`も要求値を表示するため、実効値の確定には`Bass.GetInfo(out info)`の`minbuf`・`latency`・`freq`が必要。`minbuf`は1ms丸めの推奨最小バッファ、`latency`はBASSが報告する平均遅延であり、電気入力→スピーカー発音の直接測定値ではない。

### Step 4: 挙動を固定しない採否判断

`-256`で音声が劣化・停止・ゲームが異常終了するなら**常用しない**。音切れなく同じゲーム機能が動き、明確な改善が認められたら次候補として保留し、上流BASSの実効周期・実バッファ、クラッシュ再現性を計装する。試験の結果だけで`-256`をNixの通常ランチャーに書き込まない。`-128/-64`への短縮も、現在のBASSmixのバージョン・不具合の修正状況と機能回帰テストを確認する前には恒久化しない。

2026年6月のLinuxでの問題報告はDT/NC切替、Adaptive Speed、スピナー等を含む。最終的な採用にはそれらも含むゲーム機能の回帰試験が必要だが、**危険が既知の操作をプレイ中に不用意に繰り返す必要はない**。試験前にスコア・設定を保全し、ゲームがクラッシュする前提で隔離した試験セッションを使う。

### Step 5: 詳細計装へ進むとき

標準Nixパッケージは`osu-lazer-bin`であり、実行中のBASS内部`BASS_GetInfo`を外部の`pw-top`だけでは復元できない。次の段階で、**上流ソースのデバッグビルドを別ランチャーとして並存**させ、`AudioManager.InitBass`後の`Bass.GetInfo`、`SampleChannelBass.Play`のenqueue時刻、Audio Threadでのdequeue時刻、`BassAudioMixer.ChannelPlay`到達時刻を固定長バッファへ記録する計装が必要になる。その結果があって初めて出力バッファ由来とゲーム側キュー待ち由来の差を定量的に分けられる。デバッグビルドを通常ゲーム起動へ勝手に置き換えない。

## SplitCastとの契約

neko5のゲーム音は `osu! BASS → PipeWire ALSA → ALC257` が最優先。SplitCast音声複製はアプリごとのPipeWire monitorとして下流で分岐し、ゲーム出力にリモートRTTやOBSのバッファを挟まない。neko7側にAV同期、OBS、TTS、エンコードを残す。`-256`実験によってSplitCast Captureを有効化しない。Direct ALSA `hw`への排他切替や全システム量子サイズの恒久化も行わない。

## 失敗・復旧

- `osu-lazer`が起動できない場合、現在のHome Manager launcherの存在を確認する。試験用環境変数はその他の起動には波及しない。
- 音声がなくなる、クラッシュする場合は、`-256`起動を終了し、通常の`osu-lazer`から再起動する。`~/.nixfiles`やPipeWire設定は変更されない。
- 停電・強制終了でも、この起動器には永続化する状態がない。ただし以前の`osu-audio-quantum-lab`がPipeWireのグローバル値を残した場合は別問題となる。
- `pw-metadata`の設定値0は自動選択であり、実効グラフ周期256とは両立する。`-256`を外したからといってPipeWireの量子サイズが変わるわけではない。

## 出典

- osu!framework `osu.Framework/Audio/AudioManager.cs`、`osu.Framework/Threading/AudioThread.cs`、`osu.Framework/Audio/AudioComponent.cs`、`osu.Framework/Audio/Sample/SampleChannelBass.cs`、`osu.Framework/Audio/Mixing/Bass/BassAudioMixer.cs`：https://github.com/ppy/osu-framework
- BASS update period: https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_PERIOD.html
- BASS device buffer: https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_BUFFER.html
- BASS_INFO: https://www.un4seen.com/doc/bass/BASS_INFO.html
- Historical Linux crash report (2026-06): https://github.com/ppy/osu/discussions/38001
- osu!framework BASS library update (2026-10-08): https://github.com/ppy/osu-framework/pull/6833
- SplitCast設計：`docs/graphics-streaming/ADR-2026-11-07-performance-first.md`、`docs/graphics-streaming/SPLITCAST-AGENT-PORTING-2026-11-07.md`。
